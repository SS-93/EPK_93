import { createErrorResponse } from '../utils/responses.ts'

export class ApiError extends Error {
  public status: number
  public code?: string
  public details?: any

  constructor(message: string, status: number = 500, code?: string, details?: any) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.details = details
  }
}

export class ValidationError extends ApiError {
  constructor(message: string, details?: any) {
    super(message, 422, 'VALIDATION_ERROR', details)
  }
}

export class AuthenticationError extends ApiError {
  constructor(message: string = 'Authentication required') {
    super(message, 401, 'AUTHENTICATION_ERROR')
  }
}

export class AuthorizationError extends ApiError {
  constructor(message: string = 'Insufficient permissions') {
    super(message, 403, 'AUTHORIZATION_ERROR')
  }
}

export class NotFoundError extends ApiError {
  constructor(resource: string) {
    super(`${resource} not found`, 404, 'NOT_FOUND')
  }
}

export class RateLimitError extends ApiError {
  constructor(message: string = 'Rate limit exceeded') {
    super(message, 429, 'RATE_LIMIT_ERROR')
  }
}

export function handleError(error: Error): Response {
  // Log error for debugging
  console.error('API Error:', {
    name: error.name,
    message: error.message,
    stack: error.stack,
    timestamp: new Date().toISOString()
  })

  if (error instanceof ApiError) {
    return createErrorResponse(
      error.message,
      error.status,
      {
        code: error.code,
        details: error.details
      }
    )
  }

  // Handle specific error types
  if (error.name === 'ValidationError') {
    return createErrorResponse(error.message, 422)
  }

  if (error.message.includes('JWT')) {
    return createErrorResponse('Invalid or expired token', 401)
  }

  if (error.message.includes('permission')) {
    return createErrorResponse('Insufficient permissions', 403)
  }

  if (error.message.includes('not found')) {
    return createErrorResponse(error.message, 404)
  }

  // Default to 500 for unknown errors
  return createErrorResponse(
    'Internal server error',
    500,
    { 
      originalError: error.message,
      type: error.constructor.name
    }
  )
}

export function withErrorHandling(
  handler: (req: Request, ...args: any[]) => Promise<Response>
) {
  return async (req: Request, ...args: any[]): Promise<Response> => {
    try {
      return await handler(req, ...args)
    } catch (error) {
      return handleError(error)
    }
  }
}

// Rate limiting utility
const rateLimitStore = new Map<string, { count: number; resetTime: number }>()

export function rateLimit(
  maxRequests: number = 100,
  windowMs: number = 15 * 60 * 1000 // 15 minutes
) {
  return (req: Request): Response | null => {
    const forwardedFor = req.headers.get('X-Forwarded-For')
    const realIp = req.headers.get('X-Real-IP')
    const clientIp = forwardedFor?.split(',')[0] || realIp || 'unknown'
    
    const now = Date.now()
    const key = `rate_limit:${clientIp}`
    
    const current = rateLimitStore.get(key)
    
    if (!current || now > current.resetTime) {
      rateLimitStore.set(key, {
        count: 1,
        resetTime: now + windowMs
      })
      return null
    }
    
    if (current.count >= maxRequests) {
      return createErrorResponse(
        `Rate limit exceeded. Try again in ${Math.ceil((current.resetTime - now) / 1000)} seconds.`,
        429
      )
    }
    
    current.count++
    return null
  }
}

// Cleanup old rate limit entries periodically
setInterval(() => {
  const now = Date.now()
  for (const [key, data] of rateLimitStore.entries()) {
    if (now > data.resetTime) {
      rateLimitStore.delete(key)
    }
  }
}, 60 * 1000) // Clean up every minute 