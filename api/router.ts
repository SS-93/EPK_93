import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { handleCors, addCorsHeaders } from '../middleware/cors.ts'
import { createErrorResponse, createNotFoundResponse, createSuccessResponse } from '../utils/responses.ts'
import { authRoutes } from '../Routes/auth.ts'
import { subscriptionRoutes } from '../Routes/subscriptions.ts'
import { mediaIdRoutes } from '../Routes/mediaid.ts'
import { contentRoutes } from '../Routes/content.ts'

interface RouteHandler {
  [key: string]: (req: Request, ...params: string[]) => Promise<Response>
}

const routes: { [key: string]: RouteHandler } = {
  '/auth': authRoutes,
  '/subscriptions': subscriptionRoutes,
  '/mediaid': mediaIdRoutes,
  '/content': contentRoutes
}

export async function handleRequest(req: Request): Promise<Response> {
  try {
    // Handle CORS preflight
    const corsResponse = handleCors(req)
    if (corsResponse) return corsResponse

    const url = new URL(req.url)
    const pathParts = url.pathname.split('/').filter(Boolean)
    
    if (pathParts.length === 0) {
      return createSuccessResponse({
        message: 'Bucket & MediaID API',
        version: '1.0.0',
        status: 'healthy'
      })
    }

    const baseRoute = `/${pathParts[0]}`
    const handler = routes[baseRoute]
    
    if (!handler) {
      return createNotFoundResponse('API endpoint')
    }

    // Extract method and subpath
    const method = req.method.toLowerCase()
    const subPath = pathParts.slice(1).join('/')
    
    // Route to appropriate handler
    let response: Response

    switch (baseRoute) {
      case '/auth':
        response = await routeAuth(req, method, subPath)
        break
      case '/subscriptions':
        response = await routeSubscriptions(req, method, subPath)
        break
      case '/mediaid':
        response = await routeMediaId(req, method, subPath)
        break
      case '/content':
        response = await routeContent(req, method, subPath)
        break
      default:
        response = createNotFoundResponse('API endpoint')
    }

    return addCorsHeaders(response)

  } catch (error) {
    console.error('API Error:', error)
    const errorResponse = createErrorResponse(
      'Internal server error',
      500,
      { message: error.message }
    )
    return addCorsHeaders(errorResponse)
  }
}

async function routeAuth(req: Request, method: string, subPath: string): Promise<Response> {
  switch (`${method}:${subPath}`) {
    case 'post:signup':
      return authRoutes.signup(req)
    case 'post:login':
      return authRoutes.login(req)
    case 'post:refresh':
      return authRoutes.refresh(req)
    case 'post:logout':
      return authRoutes.logout(req)
    default:
      return createNotFoundResponse('Auth endpoint')
  }
}

async function routeSubscriptions(req: Request, method: string, subPath: string): Promise<Response> {
  const parts = subPath.split('/')
  
  switch (method) {
    case 'post':
      if (subPath === 'create-checkout') {
        return subscriptionRoutes.createCheckout(req)
      }
      if (subPath === 'webhooks/stripe') {
        return subscriptionRoutes.handleStripeWebhook(req)
      }
      break
    case 'get':
      if (parts.length === 1) {
        return subscriptionRoutes.getUserSubscriptions(req, parts[0])
      }
      break
    case 'patch':
      if (parts.length === 2 && parts[1] === 'cancel') {
        return subscriptionRoutes.cancelSubscription(req, parts[0])
      }
      break
  }
  
  return createNotFoundResponse('Subscription endpoint')
}

async function routeMediaId(req: Request, method: string, subPath: string): Promise<Response> {
  switch (`${method}:${subPath}`) {
    case 'get:preferences':
      return mediaIdRoutes.getPreferences(req)
    case 'put:preferences':
      return mediaIdRoutes.updatePreferences(req)
    case 'get:analytics':
      return mediaIdRoutes.getAnalytics(req)
    case 'post:events':
      return mediaIdRoutes.logEvent(req)
    case 'delete:data':
      return mediaIdRoutes.deleteUserData(req)
    default:
      return createNotFoundResponse('MediaID endpoint')
  }
}

async function routeContent(req: Request, method: string, subPath: string): Promise<Response> {
  const parts = subPath.split('/');
  
  switch (method) {
    case 'put':
      if (parts.length === 2 && parts[1] === 'metadata') {
        return contentRoutes.updateMetadata(req, parts[0]);
      }
      if (parts.length === 2) {
        return contentRoutes.updateAlbum(req, parts[0]);
      }
      break;
    case 'get':
      if (parts.length === 2 && parts[1] === 'metadata') {
        return contentRoutes.getMetadata(req, parts[0]);
      }
      if (subPath === 'albums') {
        return contentRoutes.getAlbums(req);
      }
      if (parts.length === 2 && parts[1] === 'tracks') {
        return contentRoutes.getAlbumTracks(req, parts[0]);
      }
      if (subPath === 'bsl/eligible') {
        return contentRoutes.checkBSLEligibility(req);
      }
      if (subPath === 'bsl/tracks') {
        return contentRoutes.getBSLTracks(req);
      }
      break;
    case 'post':
      if (subPath === 'albums') {
        return contentRoutes.createAlbum(req);
      }
      if (parts.length === 2 && parts[1] === 'lyrics') {
        return contentRoutes.addLyrics(req, parts[0]);
      }
      if (parts.length === 2 && parts[1] === 'visual-clip') {
        return contentRoutes.addVisualClip(req, parts[0]);
      }
      if (subPath === 'bsl/enable') {
        return contentRoutes.enableBSL(req);
      }
      break;
    case 'delete':
      if (parts.length === 1) {
        return contentRoutes.deleteAlbum(req, parts[0]);
      }
      break;
  }
  
  return createNotFoundResponse('Content endpoint');
}

// Start the server
serve(handleRequest, { port: 8000 }) 