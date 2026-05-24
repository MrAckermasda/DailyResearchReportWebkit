import { getJson, renderEmptyState, renderMarkdownBlock, escapeHtml } from './common.js';

const app = document.querySelector('#app');

function bindArchiveHandlers(index) {
  app.querySelectorAll('[data-date]').forEach(button => {
    button.addEventListener('click', async () => {
      const date = button.dataset.date;
      history.replaceState(null, '', `#${encodeURIComponent(date)}`);
      await showDigest(index, date);
    });
  });
}

function renderArchive(index, selectedDigest, selectedDate) {
  const list = index.archive ?? [];

  app.innerHTML = `
    <section class="grid-two">
      <aside class="panel archive-list">
        <h2 class="section-title">日期归档</h2>
        <ul>
          ${list.map(item => `
            <li>
              <button class="${item.date === selectedDate ? 'active' : ''}" data-date="${escapeHtml(item.date)}">
                ${escapeHtml(item.date)}
              </button>
            </li>
          `).join('')}
        </ul>
      </aside>
      <section class="panel markdown-panel">
        <h2 class="section-title">${escapeHtml(selectedDigest?.title ?? '暂无内容')}</h2>
        ${selectedDigest ? renderMarkdownBlock(selectedDigest.rawMarkdown) : '<p class="inline-note">请选择一篇日推。</p>'}
      </section>
    </section>
  `;

  bindArchiveHandlers(index);
}

async function showDigest(index, requestedDate) {
  const fallbackDate = index.archive?.[0]?.date;
  const selectedDate = index.archive?.some(item => item.date === requestedDate) ? requestedDate : fallbackDate;

  if (!selectedDate) {
    app.innerHTML = renderEmptyState('暂无归档', '当前还没有可以展示的日推归档。');
    return;
  }

  try {
    const selectedDigest = await getJson(`/data/dashboard/digests/${selectedDate}.json`);
    renderArchive(index, selectedDigest, selectedDate);
  } catch (error) {
    renderArchive(index, null, selectedDate);
  }
}

try {
  const index = await getJson('/data/dashboard/index.json');
  if (!index.archive?.length) {
    app.innerHTML = renderEmptyState('暂无归档', '当前还没有可以展示的日推归档。');
  } else {
    const selectedDate = decodeURIComponent(location.hash.slice(1) || index.archive[0].date);
    await showDigest(index, selectedDate);
  }
} catch (error) {
  app.innerHTML = renderEmptyState('归档数据暂不可用', '请先运行 dashboard 数据构建脚本。');
}
