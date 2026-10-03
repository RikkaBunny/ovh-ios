const previewTabs = [...document.querySelectorAll('[role="tab"]')];
const previewImage = document.getElementById('preview-image');
const previewPanel = document.getElementById('preview-panel');
function selectPreview(tab, focus = false) {
  for (const item of previewTabs) {
    item.setAttribute('aria-selected', String(item === tab));
    item.tabIndex = item === tab ? 0 : -1;
  }
  previewImage.src = `assets/${tab.dataset.image}`;
  previewImage.alt = tab.dataset.description;
  previewPanel.setAttribute('aria-labelledby', tab.id);
  if (focus) tab.focus();
}
for (const [index, tab] of previewTabs.entries()) {
  tab.addEventListener('click', () => selectPreview(tab));
  tab.addEventListener('keydown', event => {
    const next = event.key === 'ArrowRight' ? (index + 1) % previewTabs.length
      : event.key === 'ArrowLeft' ? (index + previewTabs.length - 1) % previewTabs.length
      : event.key === 'Home' ? 0 : event.key === 'End' ? previewTabs.length - 1 : null;
    if (next !== null) { event.preventDefault(); selectPreview(previewTabs[next], true); }
  });
}
document.getElementById('copy-hash').addEventListener('click', async () => {
  const hash = document.getElementById('apk-hash').textContent.trim();
  const status = document.getElementById('copy-status');
  try { await navigator.clipboard.writeText(hash); status.textContent = '校验值已复制'; }
  catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(document.getElementById('apk-hash'));
    selection.removeAllRanges(); selection.addRange(range);
    status.textContent = '已选中校验值，请手动复制';
  }
});
