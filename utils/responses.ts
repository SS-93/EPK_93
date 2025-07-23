import { corsHeaders } from '../middleware/cors.ts'

interface ApiResponse<T = any> {
  success: boolean
  data?: T
  error?: string
  message?: string
  timestamp: string
}

export function createSuccessResponse<T>(
  data: T, 
  status: number = 200, 
  message?: string
): Response {
  const response: ApiResponse<T> = {
    success: true,
    data,
    message,
    timestamp: new Date().toISOString()
  }

  return new Response(JSON.stringify(response), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  })
}

export function createErrorResponse(
  error: string, 
  status: number = 400,
  details?: any
): Response {
  const response: ApiResponse = {
    success: false,
    error,
    timestamp: new Date().toISOString(),
    ...(details && { details })
  }

  return new Response(JSON.stringify(response), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  })
}

export function createPaginatedResponse<T>(
  data: T[], 
  page: number, 
  limit: number, 
  total: number
): Response {
  const response = {
    success: true,
    data,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasNext: page * limit < total,
      hasPrev: page > 1
    },
    timestamp: new Date().toISOString()
  }

  return new Response(JSON.stringify(response), {
    status: 200,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  })
}

export function createValidationErrorResponse(errors: string[]): Response {
  return createErrorResponse(
    'Validation failed',
    422,
    { validationErrors: errors }
  )
}

export function createNotFoundResponse(resource: string): Response {
  return createErrorResponse(
    `${resource} not found`,
    404
  )
}

export function createUnauthorizedResponse(message: string = 'Unauthorized'): Response {
  return createErrorResponse(message, 401)
}

export function createForbiddenResponse(message: string = 'Forbidden'): Response {
  return createErrorResponse(message, 403)
}

export function createRateLimitResponse(): Response {
  return createErrorResponse(
    'Rate limit exceeded. Please try again later.',
    429
  )
} 