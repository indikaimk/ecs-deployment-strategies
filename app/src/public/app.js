let isPolling = true;
let pollInterval = null;
let blueHits = 0;
let greenHits = 0;
const MAX_STREAM_ITEMS = 14;

// Elements
const appVersionEl = document.getElementById('app-version');
const releaseTitleEl = document.getElementById('release-title');
const releaseTagEl = document.getElementById('release-tag');
const colorCircleEl = document.getElementById('color-circle');
const colorNameEl = document.getElementById('color-name');
const healthBadgeEl = document.getElementById('health-badge');
const healthTextEl = document.getElementById('health-text');

const metaAzEl = document.getElementById('meta-az');
const metaTaskEl = document.getElementById('meta-task');
const metaRegionEl = document.getElementById('meta-region');
const metaHostEl = document.getElementById('meta-host');
const metaClusterEl = document.getElementById('meta-cluster');
const metaUptimeEl = document.getElementById('meta-uptime');

const ratioBlueFill = document.getElementById('ratio-blue-fill');
const ratioGreenFill = document.getElementById('ratio-green-fill');
const ratioBlueLabel = document.getElementById('ratio-blue-label');
const ratioGreenLabel = document.getElementById('ratio-green-label');
const trafficStreamEl = document.getElementById('traffic-stream');

const togglePollBtn = document.getElementById('toggle-poll-btn');
const clearStatsBtn = document.getElementById('clear-stats-btn');
const injectFaultBtn = document.getElementById('inject-fault-btn');
const recoverFaultBtn = document.getElementById('recover-fault-btn');
const faultAlertEl = document.getElementById('fault-alert');

// Format uptime
function formatUptime(seconds) {
  if (seconds < 60) return `${seconds}s`;
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins}m ${secs}s`;
}

// Fetch instance metadata
async function fetchInstanceInfo() {
  try {
    const res = await fetch('/api/info');
    if (!res.ok) throw new Error('Status not OK');
    const data = await res.json();

    // Set theme
    const color = (data.color || 'blue').toLowerCase();
    document.body.className = `theme-${color}`;
    colorNameEl.textContent = color.toUpperCase();

    // Set texts
    appVersionEl.textContent = data.version || 'v1.0.0';
    releaseTitleEl.textContent = data.releaseTitle || `${color.toUpperCase()} Fleet`;
    releaseTagEl.textContent = `${color.toUpperCase()} Release`;

    // Metadata
    metaAzEl.textContent = data.availabilityZone || 'us-east-1a';
    const shortTaskId = data.taskArn ? data.taskArn.split('/').pop() : data.hostname;
    metaTaskEl.textContent = shortTaskId;
    metaTaskEl.title = data.taskArn || '';
    metaRegionEl.textContent = data.region || 'us-east-1';
    metaHostEl.textContent = data.hostname || 'container';
    metaClusterEl.textContent = data.cluster || 'ecs-cluster';
    metaUptimeEl.textContent = formatUptime(data.uptimeSeconds || 0);

    // Health / Fault state
    if (data.isFaulty) {
      healthBadgeEl.className = 'badge badge-status badge-unhealthy';
      healthTextEl.textContent = 'Unhealthy (500)';
      faultAlertEl.classList.remove('hidden');
      injectFaultBtn.disabled = true;
      recoverFaultBtn.disabled = false;
    } else {
      healthBadgeEl.className = 'badge badge-status badge-healthy';
      healthTextEl.textContent = 'Healthy';
      faultAlertEl.classList.add('hidden');
      injectFaultBtn.disabled = false;
      recoverFaultBtn.disabled = true;
    }
  } catch (err) {
    console.error('Failed to load instance metadata:', err);
  }
}

// Poll ping endpoint to track traffic distribution
async function sampleTrafficPing() {
  if (!isPolling) return;

  const startTime = Date.now();
  try {
    const res = await fetch('/api/ping');
    const latency = Date.now() - startTime;
    const pill = document.createElement('div');

    if (res.ok) {
      const data = await res.json();
      const color = (data.color || 'blue').toLowerCase();
      
      if (color === 'green') {
        greenHits++;
        pill.className = 'stream-pill stream-green';
      } else {
        blueHits++;
        pill.className = 'stream-pill stream-blue';
      }

      const shortTask = (data.task || '').slice(0, 6);
      pill.textContent = `${color.toUpperCase()} (${data.version || 'v1'}) ${latency}ms`;
    } else {
      pill.className = 'stream-pill stream-err';
      pill.textContent = `ERR ${res.status} ${latency}ms`;
    }

    // Append to stream
    trafficStreamEl.prepend(pill);
    while (trafficStreamEl.children.length > MAX_STREAM_ITEMS) {
      trafficStreamEl.removeChild(trafficStreamEl.lastChild);
    }

    updateRatioBar();
  } catch (err) {
    const pill = document.createElement('div');
    pill.className = 'stream-pill stream-err';
    pill.textContent = 'NET_ERR';
    trafficStreamEl.prepend(pill);
  }
}

// Update ratio progress bar
function updateRatioBar() {
  const total = blueHits + greenHits;
  if (total === 0) {
    ratioBlueLabel.textContent = 'Blue: 100% (0 reqs)';
    ratioGreenLabel.textContent = 'Green: 0% (0 reqs)';
    ratioBlueFill.style.width = '100%';
    ratioGreenFill.style.width = '0%';
    return;
  }

  const bluePct = Math.round((blueHits / total) * 100);
  const greenPct = 100 - bluePct;

  ratioBlueLabel.textContent = `Blue: ${bluePct}% (${blueHits} reqs)`;
  ratioGreenLabel.textContent = `Green: ${greenPct}% (${greenHits} reqs)`;

  ratioBlueFill.style.width = `${bluePct}%`;
  ratioGreenFill.style.width = `${greenPct}%`;
}

// Event Listeners
togglePollBtn.addEventListener('click', () => {
  isPolling = !isPolling;
  togglePollBtn.textContent = isPolling ? 'Pause Polling' : 'Resume Polling';
});

clearStatsBtn.addEventListener('click', () => {
  blueHits = 0;
  greenHits = 0;
  trafficStreamEl.innerHTML = '';
  updateRatioBar();
});

injectFaultBtn.addEventListener('click', async () => {
  try {
    const res = await fetch('/api/fault/fail', { method: 'POST' });
    if (res.ok) {
      await fetchInstanceInfo();
    }
  } catch (err) {
    alert('Error injecting fault: ' + err.message);
  }
});

recoverFaultBtn.addEventListener('click', async () => {
  try {
    const res = await fetch('/api/fault/recover', { method: 'POST' });
    if (res.ok) {
      await fetchInstanceInfo();
    }
  } catch (err) {
    alert('Error recovering fault: ' + err.message);
  }
});

// Initialization
fetchInstanceInfo();
pollInterval = setInterval(sampleTrafficPing, 1500);
setInterval(fetchInstanceInfo, 5000);
