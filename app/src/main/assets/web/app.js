// Interface de chat. Elle ne parle jamais au reseau directement : tout passe par l'objet
// `Android` injecte par la WebView, qui est le seul chemin vers le moteur local.
(function () {
  'use strict';

  var messages = document.getElementById('messages');
  var empty = document.getElementById('empty');
  var input = document.getElementById('input');
  var composer = document.getElementById('composer');
  var btnSend = document.getElementById('btnSend');
  var btnStop = document.getElementById('btnStop');
  var banner = document.getElementById('banner');
  var statusDot = document.getElementById('statusDot');
  var settings = document.getElementById('settings');

  var pending = null; // { id, node } de la reponse en cours

  function scrollToEnd() {
    messages.scrollTop = messages.scrollHeight;
  }

  function addMessage(role, text) {
    if (empty && empty.parentNode) empty.remove();
    var node = document.createElement('div');
    node.className = 'msg ' + role;
    node.textContent = text || '';
    messages.appendChild(node);
    scrollToEnd();
    return node;
  }

  function setGenerating(on) {
    btnSend.hidden = on;
    btnStop.hidden = !on;
    input.disabled = false;
  }

  function finish() {
    if (pending && pending.caret && pending.caret.parentNode) {
      pending.caret.remove();
    }
    pending = null;
    setGenerating(false);
  }

  // Point d'entree unique appele depuis Kotlin. Le payload arrive en JSON encode.
  window.__iaEvent = function (event, payloadJson) {
    var data = JSON.parse(payloadJson);

    if (event === 'token') {
      if (!pending || pending.id !== data.id) return;
      pending.caret.insertAdjacentText('beforebegin', data.text);
      scrollToEnd();
      return;
    }

    if (event === 'done') {
      if (pending && pending.id === data.id) finish();
      return;
    }

    if (event === 'error') {
      if (pending && pending.id === data.id) {
        finish();
      }
      addMessage('error', 'Erreur : ' + data.message);
      return;
    }
  };

  // Permet a Kotlin de laisser le bouton retour fermer un panneau avant de quitter l'app.
  window.iaHandleBack = function () {
    if (!settings.hidden) {
      settings.hidden = true;
      return true;
    }
    return false;
  };

  composer.addEventListener('submit', function (e) {
    e.preventDefault();
    var text = input.value.trim();
    if (!text || pending) return;

    addMessage('user', text);
    input.value = '';
    autosize();

    var node = addMessage('assistant', '');
    var caret = document.createElement('span');
    caret.className = 'caret';
    node.appendChild(caret);

    pending = { id: String(Date.now()), node: node, caret: caret };
    setGenerating(true);
    window.Android.send(pending.id, text);
  });

  btnStop.addEventListener('click', function () {
    window.Android.stop();
  });

  // Envoi au clavier materiel ; sur clavier tactile, Entree insere un saut de ligne.
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

  document.getElementById('btnSettings').addEventListener('click', function () {
    settings.hidden = false;
  });
  document.getElementById('btnCloseSettings').addEventListener('click', function () {
    settings.hidden = true;
  });

  // Etat initial : indique clairement si un modele est charge.
  try {
    var state = JSON.parse(window.Android.getState());
    if (state.modelReady) {
      statusDot.classList.add('ready');
    } else {
      banner.hidden = false;
      banner.textContent = 'Aucun modèle installé — les réponses sont simulées pour le moment.';
    }
  } catch (e) {
    banner.hidden = false;
    banner.textContent = 'Pont natif indisponible.';
  }
})();
