// CloudFront viewer-request function for the web app (cloudfront-js-2.0).
// Client-side routes such as /inbox get index.html. /api/* only reaches this function when the
// cluster is down (otherwise its own cache behavior takes it), so it answers with a clear 503.
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (uri.startsWith('/api/')) {
    return {
      statusCode: 503,
      statusDescription: 'Service Unavailable',
      headers: {
        'content-type': { value: 'application/json' },
        'cache-control': { value: 'no-store' }
      },
      body: { encoding: 'text', data: '{"error":"offline","message":"The demo is offline."}' }
    };
  }
  if (uri.indexOf('.') === -1) {
    request.uri = '/index.html';
  }
  return request;
}
