// Gemini Canvas visual design, integrated with the existing static download service.
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
document.documentElement.classList.add('js-enabled');

const header = document.getElementById('header');
const menuButton = document.getElementById('menu-btn');
const navigation = document.getElementById('nav-menu');
const updateHeader = () => header.classList.toggle('is-scrolled', window.scrollY > 20);
window.addEventListener('scroll', updateHeader, { passive: true });
updateHeader();
function setMenu(open) {
  navigation.classList.toggle('is-active', open);
  menuButton.setAttribute('aria-expanded', String(open));
  menuButton.setAttribute('aria-label', open ? '关闭导航菜单' : '打开导航菜单');
}
menuButton.addEventListener('click', () => setMenu(menuButton.getAttribute('aria-expanded') !== 'true'));
for (const link of navigation.querySelectorAll('a')) link.addEventListener('click', () => setMenu(false));
document.addEventListener('click', event => {
  if (!header.contains(event.target)) setMenu(false);
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && menuButton.getAttribute('aria-expanded') === 'true') {
    setMenu(false);
    menuButton.focus();
  }
});
window.matchMedia('(max-width: 768px)').addEventListener('change', () => setMenu(false));

const tabs = [...document.querySelectorAll('.stage-tab-btn')];
const panels = [...document.querySelectorAll('.mockup-image')];
function selectTab(tab, focus = false) {
  for (const item of tabs) {
    item.setAttribute('aria-selected', String(item === tab));
    item.tabIndex = item === tab ? 0 : -1;
  }
  for (const panel of panels) {
    const selected = panel.id === tab.getAttribute('aria-controls');
    panel.classList.toggle('is-active', selected);
    panel.setAttribute('aria-hidden', String(!selected));
  }
  if (focus) tab.focus();
}
selectTab(tabs[0]);
for (const [index, tab] of tabs.entries()) {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', event => {
    const next = ['ArrowRight', 'ArrowDown'].includes(event.key) ? (index + 1) % tabs.length
      : ['ArrowLeft', 'ArrowUp'].includes(event.key) ? (index + tabs.length - 1) % tabs.length
      : event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : null;
    if (next !== null) {
      event.preventDefault();
      selectTab(tabs[next], true);
    }
  });
}

if ('IntersectionObserver' in window && !reducedMotion.matches) {
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    }
  }, { threshold: 0.08 });
  for (const element of document.querySelectorAll('.reveal-element')) {
    if (element.getBoundingClientRect().top < window.innerHeight) {
      element.classList.add('is-visible');
    } else {
      element.classList.add('will-reveal');
      observer.observe(element);
    }
  }
}

document.getElementById('copy-hash-btn').addEventListener('click', async () => {
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

// Complete the generated 3D particle system's animation lifecycle.
function initializeParticleStage() {
  const canvasContainer = document.getElementById('canvas-container');
  const canvas = document.getElementById('hero-canvas');
  const ctx = canvas.getContext('2d', { alpha: false });
  if (!ctx) return;
  let width, height;
  let particles = [];
  let animationFrameId = null;
  let isCanvasVisible = true;
  let timeOffset = 0;
  let lastDrawTime = 0;
  const frameInterval = 1000 / 30;

const initParticles = () => {
                width = canvasContainer.clientWidth;
                height = canvasContainer.clientHeight;

                // 限制最大 DPR = 1.5 平衡清晰度与性能
                const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
                canvas.width = width * dpr;
                canvas.height = height * dpr;
                ctx.scale(dpr, dpr);

                particles = [];
                // 桌面版 3500 粒子，移动版 1000 粒子
                const isMobile = width < 768;
                const count = isMobile ? 1000 : 3500;

                // 斐波那契球面算法生成均匀且具自然感的 3D 坐标基底
                const phi = Math.PI * (3 - Math.sqrt(5));
                const radius = isMobile ? 220 : 360;

                for (let i = 0; i < count; i++) {
                    const y = 1 - (i / (count - 1)) * 2; // -1 to 1
                    const r = Math.sqrt(1 - y * y);
                    const theta = phi * i;

                    const baseX = Math.cos(theta) * r * radius;
                    const baseY = y * (radius * 0.5); // 将球体压扁成星云环
                    const baseZ = Math.sin(theta) * r * radius;

                    // 颜色分配：从中心到边缘过渡
                    const distFromCenter = Math.sqrt(baseX*baseX + baseZ*baseZ) / radius;
                    const rCol = Math.floor(37 + (147 - 37) * distFromCenter);   // 从深蓝 0,99,235 到紫 147,51,234
                    const gCol = Math.floor(99 + (51 - 99) * distFromCenter);
                    const bCol = Math.floor(235 + (234 - 235) * distFromCenter);

                    particles.push({
                        baseX, baseY, baseZ,
                        color: `rgb(${rCol}, ${gCol}, ${bCol})`,
                        size: Math.random() * 1.5 + 0.5,
                        // 随机偏移增加云雾感
                        offsetX: (Math.random() - 0.5) * 40,
                        offsetZ: (Math.random() - 0.5) * 40,
                        speed: (Math.random() * 0.02) + 0.01 // 波动速度
                    });
                }
            };

            const drawParticles = () => {
                // 填充纯黑底色
                ctx.fillStyle = '#000000';
                ctx.fillRect(0, 0, width, height);

                // 使用 screen 混合模式实现密集处的发光效果
                ctx.globalCompositeOperation = 'screen';

                const cx = width / 2;
                const cy = height / 2;

                // 整体缓慢旋转矩阵 (绕 Y 轴)
                const rotY = timeOffset * 0.0002;
                const cosY = Math.cos(rotY);
                const sinY = Math.sin(rotY);

                // 稍微倾斜视角 (绕 X 轴)
                const tiltX = -0.3;
                const cosX = Math.cos(tiltX);
                const sinX = Math.sin(tiltX);

                for (let i = 0; i < particles.length; i++) {
                    const p = particles[i];

                    // 基于时间的 Y 轴波动 (呼吸感)
                    const waveY = Math.sin(timeOffset * p.speed * 0.03 + p.baseX * 0.01) * 20;

                    let x = p.baseX + p.offsetX;
                    let y = p.baseY + waveY;
                    let z = p.baseZ + p.offsetZ;

                    // 1. 绕 Y 轴旋转
                    const x1 = x * cosY - z * sinY;
                    const z1 = x * sinY + z * cosY;

                    // 2. 绕 X 轴倾斜
                    const y2 = y * cosX - z1 * sinX;
                    const z2 = y * sinX + z1 * cosX;

                    // 3. 3D 投影到 2D
                    const fov = 800;
                    const depth = fov + z2;
                    if (depth > 0) {
                        const scale = fov / depth;
                        const projX = cx + x1 * scale;
                        const projY = cy + y2 * scale;

                        // 深度透明度衰减，远处的点变暗
                        const alpha = Math.min(Math.max((fov - z2 * 1.5) / fov, 0.1), 1);

                        ctx.globalAlpha = alpha;
                        ctx.fillStyle = p.color;
                        // 批绘制优化：使用 fillRect 替代 arc
                        const renderedSize = p.size * scale;
                        ctx.fillRect(projX, projY, renderedSize, renderedSize);
                    }
                }

                ctx.globalAlpha = 1;
                ctx.globalCompositeOperation = 'source-over';
            };


  function animateLoop(timestamp) {
    if (!isCanvasVisible || document.hidden || reducedMotion.matches) {
      animationFrameId = null;
      return;
    }
    const elapsed = timestamp - lastDrawTime;
    if (elapsed >= frameInterval) {
      timeOffset += Math.min(elapsed, 100);
      lastDrawTime = timestamp - (elapsed % frameInterval);
      drawParticles();
    }
    animationFrameId = requestAnimationFrame(animateLoop);
  }
  function synchronizeAnimation() {
    if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
    animationFrameId = null;
    if (reducedMotion.matches) {
      drawParticles();
    } else if (isCanvasVisible && !document.hidden) {
      lastDrawTime = performance.now();
      animationFrameId = requestAnimationFrame(animateLoop);
    }
  }
  function resizeCanvas() {
    initParticles();
    drawParticles();
    synchronizeAnimation();
  }
  resizeCanvas();
  window.addEventListener('resize', resizeCanvas, { passive: true });
  document.addEventListener('visibilitychange', synchronizeAnimation);
  reducedMotion.addEventListener('change', synchronizeAnimation);
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      isCanvasVisible = entries[0].isIntersecting;
      synchronizeAnimation();
    });
    observer.observe(canvasContainer);
  }
  window.addEventListener('pagehide', () => {
    if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
    animationFrameId = null;
  });
  window.addEventListener('pageshow', synchronizeAnimation);
}
initializeParticleStage();
