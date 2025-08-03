import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from '@supabase/supabase-js'
import { corsHeaders } from '../middleware/cors.ts'
import { validateRequest } from '../middleware/validation.ts'
import { createErrorResponse, createSuccessResponse } from '../utils/responses.ts'

// ✅ FIXED: Better error handling for Vercel
const supabaseUrl = process.env.REACT_APP_SUPABASE_URL
const supabaseAnonKey = process.env.REACT_APP_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing Supabase environment variables. Please set REACT_APP_SUPABASE_URL and REACT_APP_SUPABASE_ANON_KEY in your Vercel environment variables.'
  )
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
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
      // ✅ FIXED: Better Vercel-compatible error messages
      if (error.message?.includes('placeholder') || error.message?.includes('NAME_NOT_RESOLVED')) {
        return { 
          data: null, 
          error: { 
            message: 'Environment configuration error. Please check your Vercel environment variables for REACT_APP_SUPABASE_URL and REACT_APP_SUPABASE_ANON_KEY.' 
          } 
        }
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

      // ✅ FIXED: Better redirect handling for Vercel
      const redirectTo = process.env.NODE_ENV === 'production' 
        ? `https://your-vercel-domain.vercel.app/onboarding`
        : `${window.location.origin}/onboarding`
      
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider,
        options: { redirectTo }
      })

      if (error) throw error

      return createSuccessResponse({
        session: data.session,
        message: 'OAuth login successful'
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

      // ✅ FIXED: Better redirect handling for Vercel
      const redirectTo = process.env.NODE_ENV === 'production' 
        ? `https://your-vercel-domain.vercel.app/onboarding`
        : `${window.location.origin}/onboarding`
      
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider,
        options: { redirectTo }
      })

      if (error) throw error

      return createSuccessResponse({
        session: data.session,
        message: 'OAuth sign-in successful'
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  }
} 