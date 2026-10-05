// Mushbox — shared site header: mobile nav toggle + "current page" highlight.
(function(){
  var header = document.querySelector('.mbx-site-header');
  if(!header) return;
  var toggle = header.querySelector('.mbx-nav-toggle');
  if(toggle){
    toggle.addEventListener('click', function(){
      var open = header.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }
  // "/" and "/index.html" are both the home page.
  function page(p){
    p = (p || '').split('#')[0].split('?')[0].split('/').pop();
    return (p === '' || p === 'index.html') ? 'index.html' : p;
  }
  var here = page(location.pathname);
  header.querySelectorAll('.mbx-site-nav a').forEach(function(a){
    if(page(a.getAttribute('href')) === here) a.classList.add('is-current');
  });
})();
