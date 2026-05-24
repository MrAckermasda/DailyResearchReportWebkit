import { getJson, getText, renderEmptyState, renderMarkdownBlock, escapeHtml } from './common.js';

const app = document.querySelector('#app');

function bindWeeklyHandlers(index) {
  app.querySelectorAll('[data-id]').forEach(button => {
    button.addEventListener('click', async () => {
      const reportId = button.dataset.id;
      history.replaceState(null, '', `#${encodeURIComponent(reportId)}`);
      await showReport(index, reportId);
    });
  });
}

function renderWeeklyIndex(index, selectedId, reportText) {
  const reports = index.reports ?? [];

  app.innerHTML = `
    <section class="grid-two">
      <aside class="panel report-list">
        <h2 class="section-title">周报列表</h2>
        <ul>
          ${reports.map(report => `
            <li>
              <button class="${report.id === selectedId ? 'active' : ''}" data-id="${escapeHtml(report.id)}">
                ${escapeHtml(report.id)}
              </button>
            </li>
          `).join('')}
        </ul>
      </aside>
      <section class="panel markdown-panel">
        <h2 class="section-title">${escapeHtml(selectedId ?? '暂无周报')}</h2>
        ${reportText ? renderMarkdownBlock(reportText) : '<p class="inline-note">当前没有可展示的周报初稿。</p>'}
      </section>
    </section>
  `;

  bindWeeklyHandlers(index);
}

async function showReport(index, requestedId) {
  const fallbackId = index.reports?.[0]?.id;
  const selectedId = index.reports?.some(report => report.id === requestedId) ? requestedId : fallbackId;
  const reportText = selectedId ? await getText(`/weekly-reports/${selectedId}.md`) : '';
  renderWeeklyIndex(index, selectedId, reportText);
}

try {
  const index = await getJson('/weekly-reports/index.json');
  const selectedId = decodeURIComponent(location.hash.slice(1) || index.reports?.[0]?.id || '');
  await showReport(index, selectedId);
} catch (error) {
  app.innerHTML = renderEmptyState('周报索引暂未生成', '当前还没有 weekly manifest。后续生成周报时会自动补上。');
}
