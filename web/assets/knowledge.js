import { getJson, renderEmptyState, escapeHtml, statusLabel } from './common.js';

const app = document.querySelector('#app');
const manualOverrides = [];
let selectedNodeId = null;

function branchLabel(tree, branchId) {
  return tree.topLevelBranches.find(branch => branch.id === branchId)?.label ?? branchId;
}

function renderKnowledge(tree) {
  const selectedNode = tree.nodes.find(node => node.id === selectedNodeId) ?? tree.nodes[0];
  selectedNodeId = selectedNode?.id ?? null;

  const branchMarkup = tree.topLevelBranches.map(branch => {
    const branchNodes = tree.nodes.filter(node => node.parentId === branch.id);
    return `
      <section class="tree-branch">
        <h3>${escapeHtml(branch.label)}</h3>
        <ul>
          ${branchNodes.map(node => `
            <li>
              <button class="tree-node-button ${node.id === selectedNodeId ? 'active' : ''}" data-node-id="${escapeHtml(node.id)}">
                <strong>${escapeHtml(node.label)}</strong><br>
                <span class="inline-note">${escapeHtml(statusLabel(node.status))}</span>
              </button>
            </li>
          `).join('')}
        </ul>
      </section>
    `;
  }).join('');

  const evidenceMarkup = selectedNode?.evidence?.length
    ? selectedNode.evidence.map(item => `<li>${escapeHtml(item)}</li>`).join('')
    : '<li class="inline-note">暂无证据</li>';

  app.innerHTML = `
    <section class="knowledge-layout">
      <aside class="panel knowledge-sidebar">
        <h2 class="section-title">知识树分支</h2>
        ${branchMarkup}
      </aside>
      <section class="panel knowledge-main">
        <h2 class="section-title">${escapeHtml(selectedNode?.label ?? '暂无节点')}</h2>
        <div class="badge-row">
          <span class="badge badge-${escapeHtml(selectedNode?.status ?? 'want')}">${escapeHtml(statusLabel(selectedNode?.status ?? 'want'))}</span>
          <span class="badge">${escapeHtml(branchLabel(tree, selectedNode?.parentId ?? ''))}</span>
        </div>
        <p class="inline-note">${escapeHtml(selectedNode?.notes || '这个节点还没有备注。')}</p>
        <h3>证据来源</h3>
        <ul class="node-evidence">${evidenceMarkup}</ul>
      </section>
      <section class="panel knowledge-detail">
        <h2 class="section-title">编辑当前节点</h2>
        <form class="editor" id="knowledge-editor">
          <input type="hidden" name="nodeId" value="${escapeHtml(selectedNode?.id ?? '')}">
          <label>
            <span class="inline-note">状态</span>
            <select name="status">
              ${['want', 'learning', 'learned'].map(status => `
                <option value="${status}" ${selectedNode?.status === status ? 'selected' : ''}>${escapeHtml(statusLabel(status))}</option>
              `).join('')}
            </select>
          </label>
          <label>
            <span class="inline-note">备注</span>
            <textarea name="notes">${escapeHtml(selectedNode?.notes ?? '')}</textarea>
          </label>
          <button type="submit">保存覆盖</button>
        </form>
        <p class="inline-note">当前版本支持对已有节点保存状态和备注覆盖。后续可再扩到新增节点。</p>
      </section>
    </section>
  `;

  app.querySelectorAll('[data-node-id]').forEach(button => {
    button.addEventListener('click', () => {
      selectedNodeId = button.dataset.nodeId;
      renderKnowledge(tree);
    });
  });

  document.querySelector('#knowledge-editor')?.addEventListener('submit', async event => {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    const nodeId = formData.get('nodeId');
    const status = formData.get('status');
    const notes = formData.get('notes');

    const existing = manualOverrides.find(node => node.id === nodeId);
    if (existing) {
      existing.status = status;
      existing.notes = notes;
    } else {
      manualOverrides.push({ id: nodeId, status, notes });
    }

    const response = await fetch('/api/knowledge-tree/overrides', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ nodes: manualOverrides })
    });

    if (!response.ok) {
      throw new Error('Failed to save knowledge tree overrides');
    }

    const updatedTree = await getJson('/knowledge-tree/merged-tree.json');
    renderKnowledge(updatedTree);
  });
}

try {
  const overridesResponse = await fetch('/api/knowledge-tree/overrides');
  if (overridesResponse.ok) {
    const payload = await overridesResponse.json();
    manualOverrides.splice(0, manualOverrides.length, ...(payload.nodes ?? []));
  }

  const tree = await getJson('/knowledge-tree/merged-tree.json');
  renderKnowledge(tree);
} catch (error) {
  app.innerHTML = renderEmptyState('知识树暂未生成', '先运行知识树构建脚本，页面会自动读取 merged-tree.json。');
}
