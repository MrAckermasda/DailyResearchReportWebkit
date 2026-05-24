import { getJson, renderEmptyState, renderStatCard, escapeHtml } from './common.js';

const app = document.querySelector('#app');

function renderHome(index) {
  const archiveItems = (index.archive ?? []).slice(0, 6);
  const archiveCount = index.archive?.length ?? 0;

  app.innerHTML = `
    <section class="hero">
      <h2>${escapeHtml(index.latestDigest?.date ?? '暂无最新日推')}</h2>
      <p>先处理今天和逾期任务，再回看归档、周报和知识树。</p>
    </section>
    <section class="stat-grid">
      ${renderStatCard('今日截止', index.summary?.todayCount ?? 0, 'warn')}
      ${renderStatCard('逾期任务', index.summary?.overdueCount ?? 0, 'danger')}
      ${renderStatCard('归档篇数', archiveCount, 'success')}
    </section>
    <section class="home-columns">
      <section class="panel markdown-panel">
        <h2 class="section-title">今日快照</h2>
        <ul class="summary-list">
          <li>最新日推：${escapeHtml(index.latestDigest?.title ?? '暂无')}</li>
          <li>今日截止：${escapeHtml(index.summary?.todayCount ?? 0)} 项</li>
          <li>逾期未完成：${escapeHtml(index.summary?.overdueCount ?? 0)} 项</li>
        </ul>
      </section>
      <section class="panel archive-list">
        <h2 class="section-title">最近归档</h2>
        <ul>
          ${archiveItems.map(item => `
            <li>
              <a class="action-button" href="/archive.html#${encodeURIComponent(item.date)}">
                ${escapeHtml(item.date)} · ${escapeHtml(item.title)}
              </a>
            </li>
          `).join('')}
        </ul>
      </section>
    </section>
  `;
}

try {
  const index = await getJson('/data/dashboard/index.json');
  renderHome(index);
} catch (error) {
  app.innerHTML = renderEmptyState('首页数据暂未生成', '先运行日推构建或启动脚本，页面数据准备好后会自动显示。');
}
