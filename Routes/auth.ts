import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../middleware/cors.ts'
import { validateRequest } from '../middleware/validation.ts'
import { createErrorResponse, createSuccessResponse } from '../utils/responses.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

export const authRoutes = {
  // POST /auth/signup
  async signup(req: Request): Promise<Response> {
    try {
      const { email, password, userData } = await validateRequest(req, {
        email: 'string',
        password: 'string',
        userData: 'object'
      })

      const supabase = createClient(supabaseUrl, supabaseServiceKey)

      // Create user with Supabase Auth
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: false,
        user_metadata: userData
      })

      if (authError) throw authError

      const userId = authData.user.id

      // Create profile entry
      const { error: profileError } = await supabase
        .from('profiles')
        .insert({
          id: userId,
          display_name: userData.display_name,
          role: userData.role,
          email_verified: false,
          onboarding_completed: false
        })

      if (profileError) throw profileError

      // Create MediaID entry
      const { error: mediaIdError } = await supabase
        .from('media_ids')
        .insert({
          user_uuid: userId,
          interests: [],
          genre_preferences: [],
          content_flags: {},
          privacy_settings: {
            data_sharing: true,
            location_access: false,
            audio_capture: false,
            anonymous_logging: true,
            marketing_communications: false
          }
        })

      if (mediaIdError) throw mediaIdError

      // Create role-specific entry
      if (userData.role === 'artist') {
        await supabase.from('artists').insert({
          user_id: userId,
          artist_name: userData.display_name,
          verification_status: 'pending'
        })
      } else if (userData.role === 'brand') {
        await supabase.from('brands').insert({
          user_id: userId,
          brand_name: userData.display_name,
          contact_email: email
        })
      }

      return createSuccessResponse({
        user: authData.user,
        message: 'Account created successfully. Please check your email for verification.'
      }, 201)

    } catch (error) {
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

      const supabase = createClient(supabaseUrl, supabaseServiceKey)

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

      const supabase = createClient(supabaseUrl, supabaseServiceKey)

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

      const supabase = createClient(supabaseUrl, supabaseServiceKey, {
        global: { headers: { Authorization: authHeader } }
      })

      const { error } = await supabase.auth.signOut()
      if (error) throw error

      return createSuccessResponse({
        message: 'Logout successful'
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  }
} 