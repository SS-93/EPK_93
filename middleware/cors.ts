const allowedOrigins = (Deno.env.get('CORS_ORIGINS') || 'http://localhost:3000').split(',')

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Max-Age': '86400', // 24 hours
}

export function handleCors(req: Request): Response | null {
  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { 
      headers: corsHeaders,
      status: 200 
    })
  }

  // Check origin for non-preflight requests
  const origin = req.headers.get('Origin')
  if (origin && !allowedOrigins.includes(origin) && !allowedOrigins.includes('*')) {
    return new Response('CORS: Origin not allowed', { 
      status: 403,
      headers: corsHeaders 
    })
  }

  return null
}

export function addCorsHeaders(response: Response): Response {
  const headers = new Headers(response.headers)
  Object.entries(corsHeaders).forEach(([key, value]) => {
    headers.set(key, value)
  })
  
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  })
} 