'use strict';

const form = document.getElementById('form');
const input = document.getElementById('server');
const error = document.getElementById('error');
const saveBtn = document.getElementById('save');
const forceBtn = document.getElementById('force');

window.kaif.getServer().then((s) => {
  if (s) input.value = s;
});

async function save(force) {
  error.textContent = '';
  forceBtn.hidden = true;
  saveBtn.disabled = true;
  saveBtn.textContent = 'جارٍ الاتصال...';
  try {
    const r = await window.kaif.saveServer(input.value, force);
    if (r && r.error) {
      error.textContent = r.error;
      forceBtn.hidden = !r.canForce;
    }
  } finally {
    saveBtn.disabled = false;
    saveBtn.textContent = 'اتصال';
  }
}

form.addEventListener('submit', (e) => {
  e.preventDefault();
  save(false);
});
forceBtn.addEventListener('click', () => save(true));
