// Gemini Canvas design, integrated with the existing static download service.
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
document.body.classList.add('js-enhanced');

if ('IntersectionObserver' in window && !reducedMotion.matches) {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('active');
        observer.unobserve(entry.target);
      }
    }
  }, { threshold: 0.08 });
  for (const element of document.querySelectorAll('.reveal')) {
    if (element.getBoundingClientRect().top < window.innerHeight) {
      element.classList.add('active');
    } else {
      element.classList.add('will-reveal');
      observer.observe(element);
    }
  }
}

const tabs = [...document.querySelectorAll('.tab-btn')];
const image = document.getElementById('screenshot-img');
const panel = document.getElementById('showcase-panel');
const screenshots = {
  dashboard: { src: 'assets/dashboard.png', alt: '仪表盘：活跃队列与面板主机资源占用' },
  instances: { src: 'assets/instances.png', alt: '服务器实例列表：独立服务器与 VPS' },
  control: { src: 'assets/control.png', alt: '原生实例控制：配置、电源、维护和高级操作' },
};
function selectScreenshot(tab, focus = false) {
  for (const item of tabs) {
    item.classList.toggle('active', item === tab);
    item.setAttribute('aria-selected', String(item === tab));
    item.tabIndex = item === tab ? 0 : -1;
  }
  const screenshot = screenshots[tab.dataset.target];
  image.src = screenshot.src;
  image.alt = screenshot.alt;
  panel.setAttribute('aria-labelledby', tab.id);
  if (focus) tab.focus();
}
for (const [index, tab] of tabs.entries()) {
  tab.addEventListener('click', () => selectScreenshot(tab));
  tab.addEventListener('keydown', (event) => {
    const next = ['ArrowDown', 'ArrowRight'].includes(event.key) ? (index + 1) % tabs.length
      : ['ArrowUp', 'ArrowLeft'].includes(event.key) ? (index + tabs.length - 1) % tabs.length
      : event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : null;
    if (next !== null) {
      event.preventDefault();
      selectScreenshot(tabs[next], true);
    }
  });
}

const mobileButton = document.querySelector('.mobile-menu-btn');
const navigation = document.getElementById('site-nav');
function setMenu(open) {
  navigation.classList.toggle('menu-open', open);
  mobileButton.setAttribute('aria-expanded', String(open));
  mobileButton.setAttribute('aria-label', open ? '关闭导航菜单' : '打开导航菜单');
}
mobileButton.addEventListener('click', () => setMenu(mobileButton.getAttribute('aria-expanded') !== 'true'));
for (const link of navigation.querySelectorAll('a')) link.addEventListener('click', () => setMenu(false));
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && mobileButton.getAttribute('aria-expanded') === 'true') {
    setMenu(false);
    mobileButton.focus();
  }
});
window.matchMedia('(max-width: 768px)').addEventListener('change', () => setMenu(false));

document.getElementById('copy-hash').addEventListener('click', async () => {
  const code = document.getElementById('apk-hash');
  const status = document.getElementById('copy-status');
  try {
    await navigator.clipboard.writeText(code.textContent.trim());
    status.textContent = '校验值已复制';
  } catch {
    const range = document.createRange();
    range.selectNodeContents(code);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    status.textContent = '已选中校验值，请手动复制';
  }
});
