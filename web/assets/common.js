export async function getJson(pathname) {
  const response = await fetch(pathname);
  if (!response.ok) {
    throw new Error(`Failed to load ${pathname}: ${response.status}`);
  }
  return response.json();
}

export async function getText(pathname) {
  const response = await fetch(pathname);
  if (!response.ok) {
    throw new Error(`Failed to load ${pathname}: ${response.status}`);
  }
  return response.text();
}

export function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function renderStatCard(label, value, tone = 'success') {
  return `
    <section class="panel stat stat-${tone}">
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
    </section>
  `;
}

export function renderEmptyState(title, body) {
  return `
    <section class="panel empty-state">
      <h2 class="section-title">${escapeHtml(title)}</h2>
      <p class="inline-note">${escapeHtml(body)}</p>
    </section>
  `;
}

export function renderMarkdownBlock(rawMarkdown) {
  return `<pre class="markdown-content">${escapeHtml(rawMarkdown)}</pre>`;
}

export function statusLabel(status) {
  switch (status) {
    case 'want':
      return '想学';
    case 'learning':
      return '在学';
    case 'learned':
      return '已学';
    default:
      return status;
  }
}
