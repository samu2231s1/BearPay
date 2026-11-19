(() => {
  const normalize = (value) => (value || '').trim().toLowerCase();
  document.querySelectorAll('a,button').forEach((el) => {
    const label = normalize(el.textContent);
    if (label.includes('criar conta') || label.includes('começar') || label.includes('abrir conta') || label.includes('entrar na toca')) {
      el.addEventListener('click', (event) => { event.preventDefault(); location.href = '/dashboard.html?auth=signup'; });
    } else if (label === 'entrar' || label.includes('acessar conta')) {
      el.addEventListener('click', (event) => { event.preventDefault(); location.href = '/dashboard.html?auth=login'; });
    } else if (label.includes('documentação da api')) {
      el.setAttribute('href', '/app#api');
    }
  });
})();

