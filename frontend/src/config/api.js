const isLocalhost = window.location.hostname === 'localhost' ||
  window.location.hostname === '127.0.0.1';

const API_URL = isLocalhost
  ? 'http://localhost:8000/api'  // Local dev or port-forward
  : '/api';                        // ALB with nginx proxy

export default API_URL;
