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
  var here = location.pathname.split('/').pop() || 'home.html';
  header.querySelectorAll('.mbx-site-nav a').forEach(function(a){
    var href = a.getAttribute('href').split('/').pop();
    if(href === here) a.classList.add('is-current');
  });
})();
