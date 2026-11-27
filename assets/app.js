(() => {
  'use strict';

  const REPO_OWNER = 'LianXia233';
  const REPO_NAME = 'OpenWRT-CI-H5000M';
  const PROXY_BASE = 'https://gh.acg2.mom/';
  const WALLPAPERS = window.WALLPAPERS || [
    'https://files.seeusercontent.com/2026/10/31/aE1a/145952531_p1.jpg',
    'https://files.seeusercontent.com/2026/06/29/uu4H/bg1.jpg'
  ];

  let currentDownloadMode = 'proxy';
  let latestReleasesData = [];

  function escapeHtml(str) {
    return String(str || '').replace(/[&<>"']/g, s => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[s]));
  }

  function formatDownloadUrl(rawUrl) {
    if (!rawUrl) return '';
    return currentDownloadMode === 'proxy' ? PROXY_BASE + rawUrl : rawUrl;
  }

  function formatBytes(bytes, decimals = 2) {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`;
  }

  function formatDate(dateString) {
    if (!dateString) return '';
    return new Date(dateString).toLocaleDateString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  const ASSET_RE = /^H5000M-(MT5700M|MT5700)-(\d{8})-(sysupgrade|factory|combined(?:-efi)?|image(?:-efi)?)\.(bin|itb|img\.gz|vmdk|iso)$/;
  const LEGACY_RE = /^H5000M-(MT5700M|MT5700)-.+\.(bin|itb|img\.gz|vmdk|iso)$/;

  function parseAssetName(name) {
    const n = name || '';
    const m = ASSET_RE.exec(n);
    if (m) {
      const d = m[2];
      return {
        modem: m[1],
        date: `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`,
        slug: m[3],
        ext: m[4],
        primary: m[3] === 'sysupgrade',
        legacy: false
      };
    }
    const l = LEGACY_RE.exec(n);
    if (l) {
      return { modem: l[1], date: '', slug: '', ext: l[2], primary: false, legacy: true };
    }
    return null;
  }

  function releaseMetaBadge(rel) {
    const infos = (rel.assets || []).map(a => parseAssetName(a.name)).filter(Boolean);
    if (infos.length === 0) return '';
    const parts = [];
    if (infos[0].modem) parts.push(`模组 ${infos[0].modem}`);
    if (infos[0].date) parts.push(`编译 ${infos[0].date}`);
    parts.push(`固件 ${infos.length} 个`);
    return `<div style="display:flex; flex-wrap:wrap; gap:6px;">${parts.map(x => `<span class="fw-tag-pill">${escapeHtml(x)}</span>`).join('')}</div>`;
  }

  function renderAssetList(rel) {
    const items = (rel.assets || [])
      .map(a => ({ asset: a, info: parseAssetName(a.name) }))
      .filter(x => x.info);

    if (items.length === 0) {
      return `<p style="font-size:0.84rem; color:var(--text-muted); padding:8px 0;">本 Release 暂无可识别的完整固件（可能仍在上传，或已被每日清理移除）。</p>`;
    }

    const primary = items.find(x => x.info.primary);
    return `<div class="asset-list">` + items.map(({ asset, info }) => {
      const isPrimary = !!primary && asset === primary.asset;
      const dlUrl = formatDownloadUrl(asset.browser_download_url);
      const label = isPrimary ? '主固件' : (info.slug || (info.legacy ? '旧命名' : '镜像'));
      const badgeClass = isPrimary ? 'fw-badge-fm350' : 'fw-badge-mt';
      const meta = [formatBytes(asset.size)];
      if (info.modem) meta.push(`模组 ${info.modem}`);
      if (info.date) meta.push(`编译 ${info.date}`);
      if (info.legacy) meta.push('旧命名');
      meta.push(`下载 ${asset.download_count}`);

      return `
        <div class="asset-row ${isPrimary ? 'is-primary' : ''}">
          <div style="min-width:0; flex:1;">
            <div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">
              <span class="fw-badge ${badgeClass}">${escapeHtml(label)}</span>
              <span style="font-family:var(--font-mono); font-size:0.85rem; font-weight:700; color:var(--text-main); word-break:break-all;">${escapeHtml(asset.name)}</span>
            </div>
            <div style="font-size:0.78rem; color:var(--text-muted); margin-top:4px;">
              ${meta.map(m => escapeHtml(m)).join(' · ')}
            </div>
          </div>
          <div style="display:flex; align-items:center; gap:8px; flex-shrink:0;">
            <button class="btn btn-secondary btn-sm" onclick="window.appCopy('${escapeHtml(dlUrl)}', '下载链接')" type="button">复制链接</button>
            <a href="${escapeHtml(dlUrl)}" target="_blank" rel="noopener noreferrer" class="btn btn-primary btn-sm" download>
              ${currentDownloadMode === 'proxy' ? '极速下载' : '直接下载'}
            </a>
          </div>
        </div>
      `;
    }).join('') + `</div>`;
  }

  function renderFallbackBuildStatus(errorMsg) {
    const container = document.getElementById('releases-container');
    if (!container) return;

    container.innerHTML = `
      <div class="release-block glass-card">
        ${errorMsg ? `
          <div style="padding:12px 16px; border-radius:var(--radius-md); background:var(--rose-soft); color:var(--rose-text); font-size:0.84rem;">
            <strong>云端 Release 获取失败</strong>：${escapeHtml(errorMsg)}。可点击下方「刷新检测」重试，或前往 GitHub Releases 查看。
          </div>
        ` : ''}
        <div class="release-head">
          <div>
            <div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">
              <h3 style="font-size:1.15rem; font-weight:800;">云端 Actions 自动构建中 / Release 刷新中</h3>
              <span class="fw-badge fw-badge-base">MTK-AUTO 每日构建</span>
            </div>
            <p style="font-size:0.84rem; color:var(--text-muted); margin-top:4px;">
              本项目每天 05:00 定时编译最新主线（VIKINGYFY/owrt），同时产出 MT5700 与 MT5700M 两套固件；编译完成并成功发布后，才会清理旧版本 Releases。
            </p>
          </div>
          <button class="btn btn-secondary btn-sm" onclick="window.appFetchReleases()" type="button">刷新检测</button>
        </div>
        <div class="asset-row">
          <div>
            <div style="font-family:var(--font-mono); font-weight:700; font-size:0.88rem;">H5000M-&lt;模组&gt;-&lt;YYYYMMDD&gt;-sysupgrade.bin</div>
            <div style="font-size:0.8rem; color:var(--text-muted); margin-top:2px;">每日分别产出 MT5700 / MT5700M 两套系统升级包（各集成模组管理/风扇温控/网络模式/TTYD/HomeProxy）</div>
          </div>
          <span class="fw-badge fw-badge-base">编译完毕即刻发布</span>
        </div>
        <div style="display:flex; flex-wrap:wrap; gap:10px; justify-content:flex-end;">
          <a href="https://github.com/${REPO_OWNER}/${REPO_NAME}/actions" target="_blank" rel="noopener noreferrer" class="btn btn-primary btn-sm">查看 Actions 构建流程 ↗</a>
          <a href="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases" target="_blank" rel="noopener noreferrer" class="btn btn-secondary btn-sm">前往 GitHub Releases ↗</a>
        </div>
      </div>
    `;
  }

  function renderReleases(releases) {
    const container = document.getElementById('releases-container');
    if (!container) return;

    if (!releases || releases.length === 0) {
      renderFallbackBuildStatus();
      return;
    }

    container.innerHTML = releases.map((rel, index) => {
      const isLatest = index === 0;
      const releaseDate = formatDate(rel.published_at || rel.created_at);
      const fwCount = (rel.assets || []).filter(a => parseAssetName(a.name)).length;

      return `
        <div class="release-block glass-card">
          <div class="release-head">
            <div>
              <div style="display:flex; flex-wrap:wrap; align-items:center; gap:8px;">
                <h3 style="font-size:1.2rem; font-weight:800;">${escapeHtml(rel.name || rel.tag_name)}</h3>
                ${isLatest ? '<span class="fw-badge fw-badge-fm350">最新版本 Latest</span>' : ''}
                <span class="fw-badge fw-badge-mt">${escapeHtml(rel.tag_name)}</span>
              </div>
              <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">
                发布时间：${escapeHtml(releaseDate)} ·
                <a href="${escapeHtml(rel.html_url)}" target="_blank" rel="noopener noreferrer" style="color:var(--primary); font-weight:600;">查看 GitHub Release ↗</a>
              </div>
            </div>
            <span class="fw-badge ${currentDownloadMode === 'proxy' ? 'fw-badge-fm350' : 'fw-badge-mt'}">
              ${currentDownloadMode === 'proxy' ? '⚡ 极速代理下载就绪' : '🌐 GitHub 原链直连'}
            </span>
          </div>

          ${releaseMetaBadge(rel)}
          <div style="font-size:0.78rem; font-weight:700; color:var(--text-muted); text-transform:uppercase;">可刷写固件 (${fwCount})</div>
          ${renderAssetList(rel)}

          ${rel.body ? `
            <details style="font-size:0.82rem; color:var(--text-secondary);">
              <summary style="font-weight:700; cursor:pointer;">展开构建日志与提交信息详情 ▾</summary>
              <pre style="margin-top:10px; padding:14px; border-radius:var(--radius-md); background:#f8fafc; border:1px solid var(--border-card); font-family:var(--font-mono); font-size:0.76rem; white-space:pre-wrap; overflow-x:auto;">${escapeHtml(rel.body)}</pre>
            </details>
          ` : ''}
        </div>
      `;
    }).join('');
  }

  async function fetchReleases() {
    const apiUrl = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=100`;
    try {
      const response = await fetch(apiUrl, { headers: { Accept: 'application/vnd.github.v3+json' } });
      if (!response.ok) throw new Error(`GitHub API HTTP ${response.status}`);
      const releases = await response.json();
      if (!Array.isArray(releases)) throw new Error('GitHub API 返回数据格式异常');
      latestReleasesData = releases;
      renderReleases(releases);
    } catch (err) {
      console.warn('获取 Release 异常:', err);
      renderFallbackBuildStatus(err?.message || '未知错误');
    }
  }

  let toastTimer = null;
  function showToast(msg) {
    const toast = document.getElementById('toast');
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 2600);
  }

  function copyText(text, label = '内容') {
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text)
        .then(() => showToast(`已复制${label}`))
        .catch(() => fallbackCopy(text, label));
    } else {
      fallbackCopy(text, label);
    }
  }

  function fallbackCopy(text, label) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand('copy');
      showToast(`已复制${label}`);
    } catch {
      showToast('复制失败，请手动复制');
    }
    document.body.removeChild(ta);
  }

  function getCleanProxyInput() {
    const input = document.getElementById('proxy-input')?.value.trim() || '';
    if (!input) return '';
    if (input.startsWith(PROXY_BASE)) return input.slice(PROXY_BASE.length);
    return input.replace(/^https?:\/+/, 'https://');
  }

  window.appCopy = copyText;
  window.appFetchReleases = fetchReleases;
  window.appProxyJump = () => {
    const clean = getCleanProxyInput();
    if (!clean) return showToast('请先输入有效的 GitHub 链接');
    window.open(PROXY_BASE + clean, '_blank', 'noopener,noreferrer');
  };
  window.appProxyCopyFull = () => {
    const clean = getCleanProxyInput();
    if (!clean) return showToast('请先输入有效的 GitHub 链接');
    copyText(PROXY_BASE + clean, ' ACG2 极速加速完整链接');
  };
  window.appProxyCopyPrefix = () => {
    copyText(PROXY_BASE, `加速服务前缀：${PROXY_BASE}`);
  };

  function initWallpaperControls() {
    const toggleBtn = document.getElementById('wallpaperToggleBtn');
    const panel = document.getElementById('wallpaperPanel');
    const blurSlider = document.getElementById('blurSlider');
    const blurVal = document.getElementById('blurValLabel');
    const alphaSlider = document.getElementById('alphaSlider');
    const alphaVal = document.getElementById('alphaValLabel');
    const zenBtn = document.getElementById('zenModeBtn');
    const zenExitBtn = document.getElementById('zenExitBtn');

    if (toggleBtn && panel) {
      toggleBtn.addEventListener('click', e => {
        e.stopPropagation();
        panel.classList.toggle('open');
      });
      document.addEventListener('click', e => {
        if (!panel.contains(e.target) && e.target !== toggleBtn) panel.classList.remove('open');
      });
    }

    document.querySelectorAll('.wp-thumb-btn').forEach(btn => {
      const idx = Number(btn.dataset.wpIndex);
      if (WALLPAPERS[idx] === window.currentWallpaperUrl) btn.classList.add('active');
      btn.addEventListener('click', () => {
        const url = WALLPAPERS[idx];
        if (!url) return;
        window.currentWallpaperUrl = url;
        document.documentElement.style.setProperty('--wallpaper-url', `url('${url}')`);
        document.querySelectorAll('.wp-thumb-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        showToast(`已切换至壁纸 ${idx + 1}`);
      });
    });

    document.querySelectorAll('.wp-mode-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const mode = btn.dataset.overlayMode;
        document.body.setAttribute('data-overlay', mode);
        document.querySelectorAll('.wp-mode-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        document.documentElement.style.removeProperty('--wallpaper-blur');
        document.documentElement.style.removeProperty('--card-alpha');
        const names = { standard: '标准轻透白底', clear: '极简纯白高对比', vibrant: '沉浸壁纸透视' };
        showToast(`外观模式：${names[mode] || mode}`);
      });
    });

    if (blurSlider && blurVal) {
      blurSlider.addEventListener('input', e => {
        const v = e.target.value;
        document.documentElement.style.setProperty('--wallpaper-blur', `${v}px`);
        blurVal.textContent = `${v}px`;
      });
    }

    if (alphaSlider && alphaVal) {
      alphaSlider.addEventListener('input', e => {
        const v = e.target.value;
        document.documentElement.style.setProperty('--card-alpha', (v / 100).toFixed(2));
        alphaVal.textContent = `${v}%`;
      });
    }

    const toggleZen = (enable) => {
      const next = typeof enable === 'boolean' ? enable : !document.body.classList.contains('zen-mode');
      document.body.classList.toggle('zen-mode', next);
      if (panel) panel.classList.remove('open');
      if (next) showToast('已进入纯享壁纸模式，按 ESC 退出');
    };

    if (zenBtn) zenBtn.addEventListener('click', () => toggleZen(true));
    if (zenExitBtn) zenExitBtn.addEventListener('click', () => toggleZen(false));
    window.addEventListener('keydown', e => {
      if (e.key === 'Escape' && document.body.classList.contains('zen-mode')) toggleZen(false);
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    const mobileBtn = document.getElementById('mobileMenuBtn');
    const navLinks = document.getElementById('navLinks');
    if (mobileBtn && navLinks) {
      mobileBtn.addEventListener('click', () => navLinks.classList.toggle('open'));
      navLinks.querySelectorAll('a').forEach(a => a.addEventListener('click', () => navLinks.classList.remove('open')));
    }

    const modeSwitcher = document.getElementById('downloadModeSwitcher');
    if (modeSwitcher) {
      modeSwitcher.addEventListener('click', e => {
        const btn = e.target.closest('.segment-btn');
        if (!btn) return;
        modeSwitcher.querySelectorAll('.segment-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        currentDownloadMode = btn.dataset.mode;
        renderReleases(latestReleasesData);
        showToast(currentDownloadMode === 'proxy' ? '已启用 ACG2 极速代理下载模式 (推荐)' : '已切换为 GitHub 官方源直连模式');
      });
    }

    initWallpaperControls();
    fetchReleases();
  });
})();
