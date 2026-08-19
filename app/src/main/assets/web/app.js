// Interface de chat. Elle ne parle jamais au réseau directement : tout passe par l'objet
// `Android` injecté par la WebView, qui est le seul chemin vers le moteur local.
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };

  var messages = $('messages');
  var input = $('input');
  var composer = $('composer');
  var btnSend = $('btnSend');
  var btnStop = $('btnStop');
  var banner = $('banner');
  var statusDot = $('statusDot');
  var brandLabel = $('brandLabel');

  var state = null;          // instantané renvoyé par le pont natif
  var pending = null;        // génération en cours
  var conversation = newConversation();

  // --- Utilitaires ------------------------------------------------------------

  function newConversation() {
    return { id: 'c' + Date.now(), title: '', messages: [] };
  }

  function scrollToEnd() {
    messages.scrollTop = messages.scrollHeight;
  }

  function toast(text) {
    var node = document.createElement('div');
    node.className = 'toast';
    node.textContent = text;
    document.body.appendChild(node);
    setTimeout(function () { node.remove(); }, 4000);
  }

  function formatSize(bytes) {
    if (!bytes) return '';
    var mo = bytes / (1024 * 1024);
    return mo >= 1024 ? (mo / 1024).toFixed(1) + ' Go' : Math.round(mo) + ' Mo';
  }

  // --- Rendu des messages -----------------------------------------------------

  // Rendu volontairement minimal : seuls les blocs de code sont mis en forme. Le texte
  // est toujours inséré via textContent, jamais en HTML, pour que rien de ce que produit
  // le modèle ne puisse s'exécuter dans la page.
  function renderContent(node, text) {
    node.textContent = '';
    var parts = text.split('```');
    for (var i = 0; i < parts.length; i++) {
      if (i % 2 === 0) {
        if (parts[i]) node.appendChild(document.createTextNode(parts[i]));
      } else {
        var body = parts[i];
        var newline = body.indexOf('\n');
        var code = newline >= 0 ? body.slice(newline + 1) : body;
        var pre = document.createElement('pre');
        var codeNode = document.createElement('code');
        codeNode.textContent = code;
        pre.appendChild(codeNode);
        node.appendChild(pre);
      }
    }
  }

  function addMessage(role, text) {
    var empty = $('empty');
    if (empty && empty.parentNode) empty.remove();

    var node = document.createElement('div');
    node.className = 'msg ' + role;
    if (role === 'assistant' || role === 'user') {
      renderContent(node, text || '');
    } else {
      node.textContent = text || '';
    }
    messages.appendChild(node);
    scrollToEnd();
    return node;
  }

  function addTools(text) {
    var tools = document.createElement('div');
    tools.className = 'msg-tools';

    var copy = document.createElement('button');
    copy.textContent = 'Copier';
    copy.addEventListener('click', function () {
      // Le presse-papier n'est pas accessible depuis une page file:// : on passe par une
      // zone de texte temporaire, qui fonctionne partout.
      var area = document.createElement('textarea');
      area.value = text();
      document.body.appendChild(area);
      area.select();
      try { document.execCommand('copy'); toast('Copié'); } catch (e) { toast('Copie impossible'); }
      area.remove();
    });
    tools.appendChild(copy);

    var exportBtn = document.createElement('button');
    exportBtn.textContent = 'Exporter en ZIP';
    exportBtn.addEventListener('click', function () {
      window.Android.exportProject(text(), 'projet');
    });
    tools.appendChild(exportBtn);

    messages.appendChild(tools);
    return tools;
  }

  function setGenerating(on) {
    btnSend.hidden = on;
    btnStop.hidden = !on;
  }

  function finishGeneration() {
    if (!pending) return;
    if (pending.caret && pending.caret.parentNode) pending.caret.remove();
    renderContent(pending.node, pending.text);

    var captured = pending.text;
    if (captured.trim()) {
      addTools(function () { return captured; });
      conversation.messages.push({ role: 'assistant', content: captured });
      persist();
    }
    pending = null;
    setGenerating(false);
    scrollToEnd();
  }

  function persist() {
    if (!conversation.messages.length) return;
    if (!conversation.title) {
      conversation.title = conversation.messages[0].content.slice(0, 60);
    }
    window.Android.saveConversation(
      conversation.id, conversation.title, JSON.stringify(conversation.messages));
  }

  // --- Événements venant de Kotlin -------------------------------------------

  window.__iaEvent = function (event, payloadJson) {
    var data = JSON.parse(payloadJson);

    if (event === 'token') {
      if (!pending || pending.id !== data.id) return;
      pending.text += data.text;
      // Pendant la génération, on ajoute le texte brut : reconstruire les blocs de code à
      // chaque token serait trop lourd sur un téléphone ancien.
      pending.caret.insertAdjacentText('beforebegin', data.text);
      scrollToEnd();
      return;
    }

    if (event === 'done') {
      if (pending && pending.id === data.id) finishGeneration();
      return;
    }

    if (event === 'error') {
      if (pending && pending.id === data.id) {
        if (pending.caret && pending.caret.parentNode) pending.caret.remove();
        if (!pending.text.trim() && pending.node.parentNode) pending.node.remove();
        pending = null;
        setGenerating(false);
      }
      addMessage('error', data.message);
      return;
    }

    if (event === 'step') {
      if (!pending || pending.id !== data.id) return;
      var label = document.createElement('b');
      label.textContent = data.label;
      reasoningBody().appendChild(label);
      return;
    }

    if (event === 'stepToken') {
      if (!pending || pending.id !== data.id) return;
      reasoningBody().appendChild(document.createTextNode(data.text));
      return;
    }

    if (event === 'sources') {
      var box = document.createElement('div');
      box.className = 'sources';
      for (var i = 0; i < data.results.length; i++) {
        var link = document.createElement('a');
        link.textContent = '[' + (i + 1) + '] ' + data.results[i].title;
        link.href = data.results[i].url;
        box.appendChild(link);
      }
      messages.insertBefore(box, pending ? pending.node : null);
      return;
    }

    if (event === 'download') { onDownload(data); return; }
    if (event === 'state') { applyState(JSON.parse(data.state)); return; }

    if (event === 'modelLoading') {
      showBanner('Chargement du modèle en mémoire…');
      return;
    }

    if (event === 'modelError') {
      showBanner('Modèle non chargé : ' + data.message);
      return;
    }

    if (event === 'export') {
      toast(data.ok ? data.count + ' fichiers exportés' : data.message);
      return;
    }
  };

  function reasoningBody() {
    if (!pending.reasoning) {
      var details = document.createElement('details');
      details.className = 'reasoning';
      var summary = document.createElement('summary');
      summary.textContent = 'Raisonnement';
      details.appendChild(summary);
      var body = document.createElement('div');
      body.className = 'step';
      details.appendChild(body);
      messages.insertBefore(details, pending.node);
      pending.reasoning = body;
    }
    scrollToEnd();
    return pending.reasoning;
  }

  window.iaHandleBack = function () {
    var panels = document.querySelectorAll('.panel');
    for (var i = 0; i < panels.length; i++) {
      if (!panels[i].hidden) { panels[i].hidden = true; return true; }
    }
    return false;
  };

  // --- Envoi ------------------------------------------------------------------

  composer.addEventListener('submit', function (e) {
    e.preventDefault();
    var text = input.value.trim();
    if (!text || pending) return;

    addMessage('user', text);
    conversation.messages.push({ role: 'user', content: text });
    input.value = '';
    autosize();

    var node = addMessage('assistant', '');
    var caret = document.createElement('span');
    caret.className = 'caret';
    node.appendChild(caret);

    pending = { id: String(Date.now()), node: node, caret: caret, text: '', reasoning: null };
    setGenerating(true);
    window.Android.send(pending.id, text);
  });

  btnStop.addEventListener('click', function () { window.Android.stop(); });

  input.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      composer.dispatchEvent(new Event('submit'));
    }
  });

  function autosize() {
    input.style.height = 'auto';
    input.style.height = Math.min(input.scrollHeight, window.innerHeight * 0.4) + 'px';
  }
  input.addEventListener('input', autosize);

  // --- Panneaux ---------------------------------------------------------------

  $('btnSettings').addEventListener('click', function () { $('settings').hidden = false; });
  $('btnHistory').addEventListener('click', function () {
    renderConversations();
    $('history').hidden = false;
  });
  var closers = document.querySelectorAll('[data-close]');
  for (var c = 0; c < closers.length; c++) {
    closers[c].addEventListener('click', function () {
      $(this.getAttribute('data-close')).hidden = true;
    });
  }

  $('btnNewChat').addEventListener('click', function () {
    conversation = newConversation();
    messages.textContent = '';
    var empty = document.createElement('div');
    empty.className = 'empty';
    empty.id = 'empty';
    empty.innerHTML = '<h1>Assistant informatique</h1>';
    messages.appendChild(empty);
    $('history').hidden = true;
  });

  function renderConversations() {
    var list = $('conversationList');
    list.textContent = '';
    var items = JSON.parse(window.Android.listConversations());
    for (var i = 0; i < items.length; i++) {
      (function (item) {
        var li = document.createElement('li');

        var open = document.createElement('button');
        open.className = 'title';
        open.textContent = item.title || 'Sans titre';
        open.addEventListener('click', function () { openConversation(item.id); });
        li.appendChild(open);

        var del = document.createElement('button');
        del.className = 'btn danger';
        del.textContent = '✕';
        del.addEventListener('click', function () {
          window.Android.deleteConversation(item.id);
          renderConversations();
        });
        li.appendChild(del);

        list.appendChild(li);
      })(items[i]);
    }
    if (!items.length) {
      var none = document.createElement('p');
      none.className = 'hint';
      none.textContent = 'Aucune conversation enregistrée.';
      list.appendChild(none);
    }
  }

  function openConversation(id) {
    var raw = window.Android.loadConversation(id);
    if (!raw) return;
    var data = JSON.parse(raw);
    conversation = { id: id, title: data.title, messages: data.messages || [] };

    messages.textContent = '';
    for (var i = 0; i < conversation.messages.length; i++) {
      var m = conversation.messages[i];
      var node = addMessage(m.role, m.content);
      if (m.role === 'assistant') {
        (function (content) { addTools(function () { return content; }); })(m.content);
      }
      void node;
    }
    $('history').hidden = true;
  }

  // --- Modèles ----------------------------------------------------------------

  function renderModels() {
    var container = $('modelList');
    container.textContent = '';

    $('deviceInfo').textContent =
      'Mémoire de l\'appareil : ' + state.ramMb + ' Mo — espace libre : ' +
      state.freeSpaceMb + ' Mo.';

    for (var i = 0; i < state.models.length; i++) {
      (function (model) {
        var installed = state.installedModelIds.indexOf(model.id) >= 0;
        var active = state.currentModelId === model.id;

        var card = document.createElement('div');
        card.className = 'model' + (active ? ' active' : '');
        card.id = 'model-' + model.id;

        var head = document.createElement('div');
        head.className = 'model-head';
        var name = document.createElement('b');
        name.textContent = model.label;
        if (model.id === state.recommendedModelId) {
          var tag = document.createElement('span');
          tag.className = 'tag';
          tag.textContent = 'conseillé';
          name.appendChild(tag);
        }
        if (!model.fitsInRam) {
          var warn = document.createElement('span');
          warn.className = 'tag warn';
          warn.textContent = 'RAM insuffisante';
          name.appendChild(warn);
        }
        head.appendChild(name);
        var size = document.createElement('span');
        size.className = 'model-size';
        size.textContent = formatSize(model.approxBytes);
        head.appendChild(size);
        card.appendChild(head);

        var note = document.createElement('p');
        note.className = 'hint';
        note.textContent = model.note;
        card.appendChild(note);

        var progress = document.createElement('div');
        progress.className = 'progress';
        progress.hidden = true;
        progress.appendChild(document.createElement('div'));
        card.appendChild(progress);

        var actions = document.createElement('div');
        actions.className = 'model-actions';

        if (!installed) {
          var dl = document.createElement('button');
          dl.className = 'btn primary';
          dl.textContent = 'Télécharger';
          dl.addEventListener('click', function () { window.Android.downloadModel(model.id); });
          actions.appendChild(dl);
        } else {
          if (!active) {
            var use = document.createElement('button');
            use.className = 'btn primary';
            use.textContent = 'Utiliser';
            use.addEventListener('click', function () { window.Android.activateModel(model.id); });
            actions.appendChild(use);
          } else {
            var used = document.createElement('button');
            used.className = 'btn';
            used.textContent = 'Modèle actif';
            used.disabled = true;
            actions.appendChild(used);
          }
          var rm = document.createElement('button');
          rm.className = 'btn danger';
          rm.textContent = 'Supprimer';
          rm.addEventListener('click', function () { window.Android.deleteModel(model.id); });
          actions.appendChild(rm);
        }

        card.appendChild(actions);
        container.appendChild(card);
      })(state.models[i]);
    }
  }

  function onDownload(data) {
    var card = $('model-' + data.id);
    if (!card) return;
    var progress = card.querySelector('.progress');
    var bar = progress.firstChild;

    if (data.phase === 'start') {
      progress.hidden = false;
      bar.style.width = '0%';
      showBanner('Téléchargement en cours — garde l\'application ouverte.');
    } else if (data.phase === 'progress') {
      progress.hidden = false;
      var pct = data.total > 0 ? (data.downloaded / data.total) * 100 : 0;
      bar.style.width = pct.toFixed(1) + '%';
    } else if (data.phase === 'done') {
      progress.hidden = true;
      toast('Téléchargement terminé');
    } else if (data.phase === 'error') {
      progress.hidden = true;
      addMessage('error', data.message);
      showBanner(data.message);
    } else if (data.phase === 'cancelled') {
      progress.hidden = true;
    }
  }

  $('btnImportModel').addEventListener('click', function () { window.Android.importModel(); });

  // --- Réglages ---------------------------------------------------------------

  function push(patch) {
    window.Android.updateSettings(JSON.stringify(patch));
  }

  function bindSettings() {
    var s = state.settings;

    var personaSelect = $('personaSelect');
    personaSelect.textContent = '';
    for (var i = 0; i < state.personas.length; i++) {
      var option = document.createElement('option');
      option.value = state.personas[i].id;
      option.textContent = state.personas[i].label;
      personaSelect.appendChild(option);
    }
    personaSelect.value = s.personaId;
    updatePersonaHint();

    $('systemPrompt').value = s.customSystemPrompt;
    $('passes').value = s.deliberationPasses;
    $('passesValue').textContent = s.deliberationPasses;
    $('webSearch').checked = s.webSearchEnabled;
    $('searxUrl').value = s.searxUrl;
    $('temperature').value = s.temperature;
    $('temperatureValue').textContent = Number(s.temperature).toFixed(2);
    $('maxTokens').value = s.maxTokens;
    $('maxTokensValue').textContent = s.maxTokens;
    $('promptTemplate').value = s.promptTemplate;
    $('backend').value = s.backend;
    $('hfToken').value = s.huggingFaceToken;
  }

  function updatePersonaHint() {
    var id = $('personaSelect').value;
    for (var i = 0; i < state.personas.length; i++) {
      if (state.personas[i].id === id) {
        $('personaHint').textContent = state.personas[i].description;
        return;
      }
    }
  }

  $('personaSelect').addEventListener('change', function () {
    push({ personaId: this.value });
    updatePersonaHint();
  });
  $('systemPrompt').addEventListener('change', function () {
    push({ customSystemPrompt: this.value });
  });
  $('btnResetPrompt').addEventListener('click', function () {
    $('systemPrompt').value = '';
    push({ customSystemPrompt: '' });
    toast('Prompt du profil rétabli');
  });
  $('passes').addEventListener('input', function () {
    $('passesValue').textContent = this.value;
  });
  $('passes').addEventListener('change', function () {
    push({ deliberationPasses: Number(this.value) });
  });
  $('webSearch').addEventListener('change', function () {
    push({ webSearchEnabled: this.checked });
    if (this.checked) toast('Tes questions partiront vers un moteur de recherche.');
  });
  $('searxUrl').addEventListener('change', function () { push({ searxUrl: this.value }); });
  $('temperature').addEventListener('input', function () {
    $('temperatureValue').textContent = Number(this.value).toFixed(2);
  });
  $('temperature').addEventListener('change', function () {
    push({ temperature: Number(this.value) });
  });
  $('maxTokens').addEventListener('input', function () {
    $('maxTokensValue').textContent = this.value;
  });
  $('maxTokens').addEventListener('change', function () { push({ maxTokens: Number(this.value) }); });
  $('promptTemplate').addEventListener('change', function () { push({ promptTemplate: this.value }); });
  $('backend').addEventListener('change', function () {
    push({ backend: this.value });
    toast('Le changement s\'applique au prochain chargement du modèle.');
  });
  $('hfToken').addEventListener('change', function () { push({ huggingFaceToken: this.value }); });

  // --- État global ------------------------------------------------------------

  function showBanner(text) {
    banner.hidden = !text;
    banner.textContent = text || '';
  }

  function applyState(next) {
    state = next;
    if (state.modelReady) {
      statusDot.classList.add('ready');
      showBanner('');
      for (var i = 0; i < state.models.length; i++) {
        if (state.models[i].id === state.currentModelId) brandLabel.textContent = state.models[i].label;
      }
    } else {
      statusDot.classList.remove('ready');
      brandLabel.textContent = 'IA Locale';
      showBanner('Aucun modèle chargé. Ouvre les réglages pour en installer un.');
    }
    renderModels();
    bindSettings();
  }

  try {
    applyState(JSON.parse(window.Android.getState()));
  } catch (e) {
    showBanner('Pont natif indisponible : ' + e.message);
  }
})();
