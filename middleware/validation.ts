interface ValidationSchema {
  [key: string]: 'string' | 'number' | 'boolean' | 'object' | 'array'
}

export class ValidationError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'ValidationError'
  }
}

export async function validateRequest(req: Request, schema: ValidationSchema): Promise<any> {
  let body: any

  try {
    body = await req.json()
  } catch {
    throw new ValidationError('Invalid JSON in request body')
  }

  const errors: string[] = []

  for (const [field, type] of Object.entries(schema)) {
    const value = body[field]

    if (value === undefined || value === null) {
      errors.push(`Missing required field: ${field}`)
      continue
    }

    if (!validateType(value, type)) {
      errors.push(`Invalid type for field ${field}: expected ${type}, got ${typeof value}`)
    }
  }

  if (errors.length > 0) {
    throw new ValidationError(`Validation failed: ${errors.join(', ')}`)
  }

  return body
}

function validateType(value: any, expectedType: string): boolean {
  switch (expectedType) {
    case 'string':
      return typeof value === 'string' && value.length > 0
    case 'number':
      return typeof value === 'number' && !isNaN(value)
    case 'boolean':
      return typeof value === 'boolean'
    case 'object':
      return typeof value === 'object' && value !== null && !Array.isArray(value)
    case 'array':
      return Array.isArray(value)
    default:
      return false
  }
}

export function validateEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  return emailRegex.test(email)
}

export function validatePassword(password: string): { valid: boolean; errors: string[] } {
  const errors: string[] = []

  if (password.length < 8) {
    errors.push('Password must be at least 8 characters long')
  }

  if (!/[A-Z]/.test(password)) {
    errors.push('Password must contain at least one uppercase letter')
  }

  if (!/[a-z]/.test(password)) {
    errors.push('Password must contain at least one lowercase letter')
  }

  if (!/\d/.test(password)) {
    errors.push('Password must contain at least one number')
  }

  return {
    valid: errors.length === 0,
    errors
  }
}

export function validateFileUpload(file: File): { valid: boolean; errors: string[] } {
  const errors: string[] = []
  const maxSize = parseInt(Deno.env.get('MAX_FILE_SIZE') || '52428800') // 50MB
  const allowedTypes = (Deno.env.get('ALLOWED_FILE_TYPES') || '').split(',')

  if (file.size > maxSize) {
    errors.push(`File size exceeds maximum allowed size of ${maxSize} bytes`)
  }

  if (allowedTypes.length > 0 && !allowedTypes.includes(file.type)) {
    errors.push(`File type ${file.type} is not allowed`)
  }

  return {
    valid: errors.length === 0,
    errors
  }
} 