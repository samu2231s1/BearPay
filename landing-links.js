(() => {
  const normalize = (value) => (value || '').trim().toLowerCase();
  document.querySelectorAll('a,button').forEach((el) => {
    const label = normalize(el.textContent);
    if (label.includes('criar conta') || label.includes('começar agora') || label.includes('abrir conta')) {
      el.addEventListener('click', (event) => { event.preventDefault(); location.href = '/cadastro'; });
    } else if (label === 'entrar' || label.includes('acessar conta')) {
      el.addEventListener('click', (event) => { event.preventDefault(); location.href = '/login'; });
    } else if (label.includes('documentação da api')) {
      el.setAttribute('href', '/app#api');
    }
  });
})();

