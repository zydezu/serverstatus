let servers = [
    { id: 1, name: "basil", url: "https://status.boysare.moe/basil" },
    { id: 2, name: "sunny", url: "https://status.boysare.moe/sunny" }
];
let timer = null;
let data = {};

const PROC_LIMIT_MIN = 5;
const PROC_LIMIT_MAX = 10;
const PROC_LIMIT_KEY = 'serverstatus:procLimit';

function barColor(pct) {
    if (pct >= 90) return 'crit';
    if (pct >= 70) return 'warn';
    return '';
}

function fmtUptime(s) {
    const text = "uptime:";
    if (!s && s !== 0) return '\u2014';
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
    if (d > 0) return `${text} ${d}d ${h}h`;
    if (h > 0) return `${text} ${h}h ${m}m`;
    return `${text} ${m}m`;
}

function fmtBytes(kb) {
    const gb = kb / 1024 / 1024;
    return gb >= 1 ? `${gb.toFixed(1)}GB` : `${(kb / 1024).toFixed(0)}MB`;
}

function fmtRate(bytesPerSec) {
    if (bytesPerSec == null) return '—';
    const bps = bytesPerSec * 8;
    if (bps >= 1e9) return `${(bps / 1e9).toFixed(1)} Gb/s`;
    if (bps >= 1e6) return `${(bps / 1e6).toFixed(1)} Mb/s`;
    if (bps >= 1e3) return `${(bps / 1e3).toFixed(0)} kb/s`;
    return `${Math.round(bps)} b/s`;
}

function fmtTimestamp(ts) {
    if (!ts) return '';
    return 'updated ' + new Date(ts * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function renderDisks(disks) {
    if (!disks || !disks.length) return '';
    const items = disks.map(disk => {
        const pct = Math.round(disk.pct);
        const color = barColor(pct);
        const devShort = disk.dev.replace('/dev/', '');
        return `
        <div class="disk">
          <div class="metric-label">
            <span class="disk-name" title="${disk.dev}"><i class="ti ti-server" aria-hidden="true"></i> ${devShort}</span>
            <span class="metric-val">${pct}%</span>
          </div>
          <div class="bar-track"><div class="bar-fill disk ${color}" style="width:${pct}%"></div></div>
          <div class="disk-sub">${fmtBytes(disk.used)}/${fmtBytes(disk.total)}</div>
        </div>`;
    }).join('');
    return `<div class="disks">${items}</div>`;
}

function renderNet(net) {
    if (!net) return '';
    return `
    <div class="side-net">
      <span class="net-down"><i class="ti ti-arrow-down" aria-hidden="true"></i>${fmtRate(net.rx_bps)}</span>
      <span class="net-up"><i class="ti ti-arrow-up" aria-hidden="true"></i>${fmtRate(net.tx_bps)}</span>
    </div>`;
}

function renderPower(watts) {
    if (watts == null) return '';
    return `
    <div class="side-power" title="CPU package power (RAPL)">
      <i class="ti ti-bolt" aria-hidden="true"></i>${watts.toFixed(1)} W
    </div>`;
}

function shortCpuModel(model) {
    return model
        .replace(/\((?:R|TM|r|tm)\)/g, '')
        .replace(/\s*(?:CPU\s*)?@\s*[\d.]+\s*GHz/i, '')
        .replace(/\s+with\s+.*$/i, '')
        .replace(/\s+/g, ' ')
        .trim();
}

function renderCpuInfo(info) {
    if (!info || !info.model) return '';
    const topology = [];
    if (info.cores) topology.push(`${info.cores}c`);
    if (info.threads) topology.push(`${info.threads}t`);
    const suffix = topology.length ? ` <span class="metric-sub">${topology.join('/')}</span>` : '';
    return ` <span class="cpu-spec" title="${info.model}">${shortCpuModel(info.model)}${suffix}</span>`;
}

let procLimit = readProcLimit();

function readProcLimit() {
    let stored = null;
    try { stored = localStorage.getItem(PROC_LIMIT_KEY); } catch (e) { /* private mode */ }
    return parseInt(stored, 10) === PROC_LIMIT_MAX ? PROC_LIMIT_MAX : PROC_LIMIT_MIN;
}

function toggleProcLimit() {
    procLimit = procLimit >= PROC_LIMIT_MAX ? PROC_LIMIT_MIN : PROC_LIMIT_MAX;
    try { localStorage.setItem(PROC_LIMIT_KEY, String(procLimit)); } catch (e) { /* private mode */ }
    renderGrid();
}

function renderProcToggle() {
    const expanded = procLimit >= PROC_LIMIT_MAX;
    const longest = Math.max(
        ...servers.map(sv => {
            const d = data[sv.id];
            if (!d || d.error) return 0;
            return Math.max(d.top_cpu ? d.top_cpu.length : 0, d.top_mem ? d.top_mem.length : 0);
        })
    );
    if (longest <= PROC_LIMIT_MIN) return '';
    return `
    <button type="button" class="proc-toggle${expanded ? ' expanded' : ''}" aria-expanded="${expanded}"
        aria-label="${expanded ? 'Show fewer processes' : `Show all ${PROC_LIMIT_MAX} processes`}"
        title="${expanded ? 'show fewer' : `show all ${PROC_LIMIT_MAX}`}">
        <i class="ti ti-chevron-down" aria-hidden="true"></i>
    </button>`;
}

function renderProcesses(procs, key, count) {
    if (!procs || !procs.length) return '';
    return `
    <div class="proc-list">
        <div class="proc-header">${key}${count != null ? ` <span class="metric-sub">(${count})</span>` : ''}</div>
        ${procs.slice(0, procLimit).map(p => `
        <div class="proc-row">
            <span class="proc-name" title="${p.name}">${p.name}${p.procs > 1 ? ` <span class="metric-sub">×${p.procs}</span>` : ''}</span>
            <span class="proc-val">${key === 'cpu' ? p.cpu + '%' : p.mem_mb + ' MB'}</span>
        </div>`).join('')}
    </div>`;
}

function renderGrid() {
    const grid = document.getElementById('server-grid');
    grid.innerHTML = servers.map(sv => {
        const d = data[sv.id];
        const status = !d ? 'fetching' : d.error ? 'offline' : 'online';
        const cpu = d && !d.error ? Math.round(d.cpu) : null;
        const ram = d && !d.error ? Math.round(d.ram) : null;
        const ramUsed = d && !d.error && d.ram_used_mb ? d.ram_used_mb : null;
        const ramTotal = d && !d.error && d.ram_total_mb ? d.ram_total_mb : null;
        const procCount = d && !d.error && d.proc_count != null ? d.proc_count : null;
        const cpuColor = cpu !== null ? barColor(cpu) : '';
        const ramColor = ram !== null ? barColor(ram) : '';
        return `
      <div class="server-card${status === 'offline' ? ' offline' : ''}">
        <div class="card-header">
          <div>
            <div class="server-title-row"><span class="status-dot ${status}"></span><div class="server-name" title="${sv.url}">${sv.name}</div></div>
            <div class="server-addr"><a href="${sv.url}" target="_blank" rel="noopener">View JSON</a></div>
          </div>
          <div class="card-side">
            ${status === 'online' ? `
            <span class="side-stats">
              ${renderNet(d.net)}
            </span>` : ''}
          </div>
        </div>
        ${status === 'online' ? `
        <div class="metric-row">
          <div class="metric-label"><span class="metric-name"><i class="ti ti-cpu" aria-hidden="true"></i> cpu${renderCpuInfo(d.cpu_info)}</span><span class="metric-val">${cpu}%</span></div>
          <div class="bar-track"><div class="bar-fill cpu ${cpuColor}" style="width:${cpu}%"></div></div>
        </div>
        <div class="metric-row">
          <div class="metric-label"><span><i class="ti ti-device-desktop-analytics" aria-hidden="true"></i> ram</span><span class="metric-val">${ram}%${ramUsed !== null ? ` \u00b7 ${ramUsed}/${ramTotal} MB` : ''}</span></div>
          <div class="bar-track"><div class="bar-fill ram ${ramColor}" style="width:${ram}%"></div></div>
        </div>
        ${renderDisks(d.disks)}
        <div class="processes">
          ${d.top_cpu ? renderProcesses(d.top_cpu, 'cpu', procCount) : ''}
          ${d.top_mem ? renderProcesses(d.top_mem, 'mem') : ''}
        </div>
        ${renderProcToggle()}
        <div class="uptime">${fmtUptime(d.uptime_s)}${d.timestamp ? ` &middot; ${fmtTimestamp(d.timestamp)}` : ''}</div>
        ` : status === 'offline' ? `
        <div class="error-msg">${d && d.errMsg ? d.errMsg : 'could not reach metrics.json'}</div>
        ` : `<div style="font-size:12px;color:var(--color-text-tertiary);margin-top:8px;">fetching\u2026</div>`}
      </div>`;
    }).join('');

    const dot = document.getElementById('global-dot');
    if (dot) dot.className = 'status-dot' +
        (servers.every(s => data[s.id] && data[s.id].error) ? ' error' : '');
}

async function fetchOne(sv) {
    if (!sv.url) return;
    try {
        const res = await fetch(sv.url, { cache: 'no-store' });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json = await res.json();
        data[sv.id] = json;
    } catch (e) {
        data[sv.id] = { error: true, errMsg: e.message };
    }
}

let firstLoad = true;

async function fetchAll() {
    await Promise.all(servers.map(fetchOne));
    if (firstLoad) {
        const grid = document.getElementById('server-grid');
        grid.classList.add('first-load');
        setTimeout(() => grid.classList.remove('first-load'), 800);
        firstLoad = false;
    }
    renderGrid();
}

function startTimer() {
    if (timer) clearInterval(timer);
    timer = setInterval(fetchAll, 4000);
}

document.addEventListener('click', e => {
    if (!e.target.closest('.proc-toggle')) return;
    toggleProcLimit();
});

fetchAll();
startTimer();
