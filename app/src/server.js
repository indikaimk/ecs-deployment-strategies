const express = require('express');
const os = require('os');
const path = require('path');
const http = require('http');

const app = express();
const server = http.createServer(app);

// Configuration & Environment Variables
const PORT = parseInt(process.env.PORT || '3000', 10);
const APP_VERSION = process.env.APP_VERSION || 'v1.0.0';
const APP_COLOR = (process.env.APP_COLOR || 'blue').toLowerCase();
const APP_RELEASE_TITLE = process.env.APP_RELEASE_TITLE || 'Blue Release';
const AWS_REGION = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1';

// Dynamic ECS Metadata cache
let ecsMetadata = {
  taskArn: process.env.ECS_TASK_ARN || 'local-task',
  availabilityZone: process.env.ECS_AVAILABILITY_ZONE || 'local-az',
  cluster: process.env.ECS_CLUSTER || 'local-cluster',
  containerId: os.hostname(),
};

// State flags
let isFaulty = false;
let isShuttingDown = false;
const startTime = Date.now();

// Query AWS ECS Task Metadata v4 if running in ECS Fargate
async function fetchECSMetadata() {
  const metadataUri = process.env.ECS_CONTAINER_METADATA_URI_V4;
  if (!metadataUri) {
    return;
  }

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2000);
    const response = await fetch(`${metadataUri}/task`, { signal: controller.signal });
    clearTimeout(timeout);

    if (response.ok) {
      const data = await response.json();
      ecsMetadata = {
        taskArn: data.TaskARN || ecsMetadata.taskArn,
        availabilityZone: data.AvailabilityZone || ecsMetadata.availabilityZone,
        cluster: data.Cluster || ecsMetadata.cluster,
        containerId: (data.Containers && data.Containers[0] && data.Containers[0].DockerId)
          ? data.Containers[0].DockerId.slice(0, 12)
          : os.hostname(),
      };
      console.log('Successfully fetched ECS metadata:', ecsMetadata);
    }
  } catch (err) {
    console.warn('Could not fetch ECS metadata endpoint (normal for local dev):', err.message);
  }
}

// Initial metadata fetch
fetchECSMetadata();

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Middleware to inject version & color header into every HTTP response
app.use((req, res, next) => {
  res.setHeader('X-App-Version', APP_VERSION);
  res.setHeader('X-App-Color', APP_COLOR);
  next();
});

// ALB Health Check Endpoint
app.get('/health', (req, res) => {
  if (isShuttingDown) {
    return res.status(503).json({
      status: 'SHUTTING_DOWN',
      message: 'Container is draining connections'
    });
  }

  if (isFaulty) {
    return res.status(500).json({
      status: 'UNHEALTHY',
      faultInjected: true,
      message: 'Simulated failure active to trigger CloudWatch Alarm rollback'
    });
  }

  return res.status(200).json({
    status: 'HEALTHY',
    version: APP_VERSION,
    color: APP_COLOR,
    uptimeSeconds: Math.floor((Date.now() - startTime) / 1000)
  });
});

// JSON Metadata Endpoint for Dashboard and Polling
app.get('/api/info', (req, res) => {
  res.json({
    version: APP_VERSION,
    color: APP_COLOR,
    releaseTitle: APP_RELEASE_TITLE,
    region: AWS_REGION,
    hostname: os.hostname(),
    containerId: ecsMetadata.containerId,
    taskArn: ecsMetadata.taskArn,
    availabilityZone: ecsMetadata.availabilityZone,
    cluster: ecsMetadata.cluster,
    uptimeSeconds: Math.floor((Date.now() - startTime) / 1000),
    isFaulty,
    isShuttingDown,
    timestamp: new Date().toISOString()
  });
});

// Lightweight Ping Endpoint for Traffic Generators
app.get('/api/ping', (req, res) => {
  if (isFaulty) {
    return res.status(500).json({ error: 'Fault injected' });
  }
  res.json({
    ok: true,
    version: APP_VERSION,
    color: APP_COLOR,
    task: ecsMetadata.taskArn.split('/').pop() || os.hostname(),
    az: ecsMetadata.availabilityZone,
    time: Date.now()
  });
});

// Chaos Engineering / Fault Injection Endpoints
app.post('/api/fault/toggle', (req, res) => {
  isFaulty = !isFaulty;
  res.json({
    isFaulty,
    message: isFaulty
      ? 'Fault injected: /health and /api/ping now return HTTP 500'
      : 'Fault removed: Services restored to HTTP 200'
  });
});

app.post('/api/fault/fail', (req, res) => {
  isFaulty = true;
  res.json({ isFaulty: true, message: 'Fault injected: /health now returns HTTP 500' });
});

app.post('/api/fault/recover', (req, res) => {
  isFaulty = false;
  res.json({ isFaulty: false, message: 'Fault removed: /health now returns HTTP 200' });
});

// Start Server
server.listen(PORT, '0.0.0.0', () => {
  console.log(`===============================================`);
  console.log(`ECS Demo Web App started on port ${PORT}`);
  console.log(`Version : ${APP_VERSION}`);
  console.log(`Color   : ${APP_COLOR}`);
  console.log(`Title   : ${APP_RELEASE_TITLE}`);
  console.log(`Arch    : ${os.arch()}`);
  console.log(`===============================================`);
});

// Graceful Shutdown handling for ECS Fargate deregistration delay
function gracefulShutdown(signal) {
  console.log(`Received ${signal}. Starting graceful shutdown...`);
  isShuttingDown = true;

  // Stop accepting new connections
  server.close(() => {
    console.log('HTTP server closed. Exiting process.');
    process.exit(0);
  });

  // Force exit after 15 seconds if in-flight requests don't finish
  setTimeout(() => {
    console.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 15000).unref();
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

module.exports = { app, server };
