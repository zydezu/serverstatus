let servers = [
    { id: 1, name: "basil", url: "http://localhost:9090/basil" },
    { id: 2, name: "cali", url: "http://localhost:9090/cali" }
];
let timer = null;
let data = {};

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

function fmtTimestamp(ts) {
    if (!ts) return '';
    return 'updated ' + new Date(ts * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function renderDisks(disks) {
    if (!disks || !disks.length) return '';
    return disks.map(disk => {
        const pct = Math.round(disk.pct);
        const color = barColor(pct);
        const devShort = disk.dev.replace('/dev/', '');
        return `
        <div class="metric-row">
          <div class="metric-label">
            <span><i class="ti ti-server" aria-hidden="true"></i> ${devShort}</span>
            <span class="metric-val">${pct}% &middot; ${fmtBytes(disk.used)}/${fmtBytes(disk.total)}</span>
          </div>
          <div class="bar-track"><div class="bar-fill disk ${color}" style="width:${pct}%"></div></div>
        </div>`;
    }).join('');
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
            <div class="server-name">${sv.name}</div>
            <div class="server-addr"><a href="${sv.url}" target="_blank" rel="noopener">${sv.url.replace(/\/metrics\.json$/, '')}</a></div>
          </div>
          <span class="badge ${status}">${status}</span>
        </div>
        ${status === 'online' ? `
        <div class="metric-row">
          <div class="metric-label"><span><i class="ti ti-cpu" aria-hidden="true"></i> cpu${procCount !== null ? ` <span class="metric-sub">(${procCount})</span>` : ''}</span><span class="metric-val">${cpu}%</span></div>
          <div class="bar-track"><div class="bar-fill cpu ${cpuColor}" style="width:${cpu}%"></div></div>
        </div>
        <div class="metric-row">
          <div class="metric-label"><span><i class="ti ti-device-desktop-analytics" aria-hidden="true"></i> ram</span><span class="metric-val">${ram}%${ramUsed !== null ? ` \u00b7 ${ramUsed}/${ramTotal} MB` : ''}</span></div>
          <div class="bar-track"><div class="bar-fill ram ${ramColor}" style="width:${ram}%"></div></div>
        </div>
        ${renderDisks(d.disks)}
        <div class="uptime">${fmtUptime(d.uptime_s)}${d.timestamp ? ` &middot; ${fmtTimestamp(d.timestamp)}` : ''}</div>
        ` : status === 'offline' ? `
        <div class="error-msg">${d && d.errMsg ? d.errMsg : 'could not reach metrics.json'}</div>
        ` : `<div style="font-size:12px;color:var(--color-text-tertiary);margin-top:8px;">fetching\u2026</div>`}
      </div>`;
    }).join('');

    document.getElementById('global-dot').className = 'status-dot' + (servers.every(s => data[s.id] && data[s.id].error) ? ' error' : '');
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

async function fetchAll() {
    await Promise.all(servers.map(fetchOne));
    renderGrid();
}

function startTimer() {
    if (timer) clearInterval(timer);
    timer = setInterval(fetchAll, 2000);
}

renderGrid();
fetchAll();
startTimer();
