package main

// swaggerUIPage renders Swagger UI (loaded from a public CDN) against our hand-authored
// docs/openapi.yaml spec — pragmatic choice over annotating ~70 handlers with swaggo
// comments one by one for the same end result (an interactive API doc at GET /docs).
const swaggerUIPage = `<!DOCTYPE html>
<html>
<head>
  <title>One Bharat Export-Import API Docs</title>
  <meta charset="utf-8"/>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.onload = function() {
      SwaggerUIBundle({
        url: '/docs/openapi.yaml',
        dom_id: '#swagger-ui',
        presets: [SwaggerUIBundle.presets.apis],
      });
    };
  </script>
</body>
</html>`
