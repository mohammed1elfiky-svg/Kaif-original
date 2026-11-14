'use strict';

const q = new URLSearchParams(location.search);
document.getElementById('detail').textContent = [q.get('server'), q.get('error')].filter(Boolean).join(' — ');
document.getElementById('retry').addEventListener('click', () => window.kaif.retry());
document.getElementById('change').addEventListener('click', () => window.kaif.changeServer());

// tries again automatically every 30 seconds
setInterval(() => window.kaif.retry(), 30000);
