import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from '@supabase/supabase-js'
import { corsHeaders } from '../middleware/cors.ts'
import { validateRequest } from '../middleware/validation.ts'
import { createErrorResponse, createSuccessResponse } from '../utils/responses.ts'

// ✅ FIXED: Backend uses service role key for admin operations
const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!supabaseUrl || !supabaseServiceKey) {
  throw new Error(
    'Missing Supabase environment variables. Please set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY for backend operations.'
  )
}

export const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
})

export const authRoutes = {
  // POST /auth/signup
  async signup(req: Request): Promise<Response> {
    try {
      const { email, password, userData } = await validateRequest(req, {
        email: 'string',
        password: 'string',
        userData: 'object'
      })

      // ✅ FIXED: Only create user - let trigger handle profile/MediaID
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: false,
        user_metadata: userData  // ✅ Trigger will use this data
      })

      if (authError) throw authError

      const userId = authData.user.id

      // ✅ FIXED: Only create role-specific entries (not handled by trigger)
      if (userData.role === 'artist') {
        const { error: artistError } = await supabase.from('artists').insert({
          user_id: userId,
          artist_name: userData.display_name,
          verification_status: 'pending'
        })
        if (artistError) throw artistError
        
      } else if (userData.role === 'brand') {
        const { error: brandError } = await supabase.from('brands').insert({
          user_id: userId,
          brand_name: userData.display_name,
          contact_email: email
        })
        if (brandError) throw brandError
      }
      // ✅ Added: developer and admin roles work with just profile/MediaID

      return createSuccessResponse({
        user: authData.user,
        message: 'Account created successfully. Please check your email for verification.'
      }, 201)

    } catch (error) {
      // ✅ FIXED: Better backend error messages
      if (error.message?.includes('placeholder') || error.message?.includes('NAME_NOT_RESOLVED')) {
        return createErrorResponse(
          'Environment configuration error. Please check your backend environment variables for SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.',
          500
        )
      }
      return createErrorResponse(error.message, 400)
    }
  },

  // POST /auth/login
  async login(req: Request): Promise<Response> {
    try {
      const { email, password } = await validateRequest(req, {
        email: 'string',
        password: 'string'
      })

      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password
      })

      if (error) throw error

      return createSuccessResponse({
        user: data.user,
        session: data.session,
        message: 'Login successful'
      })

    } catch (error) {
      return createErrorResponse(error.message, 401)
    }
  },

  // POST /auth/refresh
  async refresh(req: Request): Promise<Response> {
    try {
      const { refresh_token } = await validateRequest(req, {
        refresh_token: 'string'
      })

      const { data, error } = await supabase.auth.refreshSession({
        refresh_token
      })

      if (error) throw error

      return createSuccessResponse({
        session: data.session,
        message: 'Token refreshed successfully'
      })

    } catch (error) {
      return createErrorResponse(error.message, 401)
    }
  },

  // POST /auth/logout
  async logout(req: Request): Promise<Response> {
    try {
      const authHeader = req.headers.get('Authorization')
      if (!authHeader) throw new Error('No authorization header')

      const { error } = await supabase.auth.signOut()
      if (error) throw error

      return createSuccessResponse({
        message: 'Logout successful'
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // POST /auth/oauth/:provider
  async oauth(req: Request): Promise<Response> {
    try {
      const { provider } = await validateRequest(req, {
        provider: 'string'
      })

      // ✅ FIXED: Better redirect handling using APP_URL
      const redirectTo = process.env.APP_URL 
        ? `${process.env.APP_URL}/onboarding`
        : `http://localhost:3000/onboarding`
      
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider,
        options: { redirectTo }
      })

      if (error) throw error

      return createSuccessResponse({
        url: data.url,
        provider: data.provider,
        message: 'OAuth login initiated'
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // POST /auth/signin/:provider
  async signInWithOAuth(req: Request): Promise<Response> {
    try {
      const { provider } = await validateRequest(req, {
        provider: 'string'
      })

      // ✅ FIXED: Better redirect handling using APP_URL
      const redirectTo = process.env.APP_URL 
        ? `${process.env.APP_URL}/onboarding`
        : `http://localhost:3000/onboarding`
      
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider,
        options: { redirectTo }
      })

      if (error) throw error

      return createSuccessResponse({
        url: data.url,
        provider: data.provider,
        message: 'OAuth sign-in initiated'
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  }
} 