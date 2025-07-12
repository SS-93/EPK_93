import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface SignupRequest {
  email: string
  password: string
  userData: {
    display_name: string
    role: 'fan' | 'artist' | 'brand'
  }
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { email, password, userData }: SignupRequest = await req.json()

    // Create user with Supabase Auth
    const { data: authData, error: authError } = await supabaseClient.auth.admin.createUser({
      email,
      password,
      email_confirm: false, // We'll handle verification
      user_metadata: userData
    })

    if (authError) throw authError

    const userId = authData.user.id

    // Create profile entry
    const { error: profileError } = await supabaseClient
      .from('profiles')
      .insert({
        id: userId,
        display_name: userData.display_name,
        role: userData.role,
        email_verified: false,
        onboarding_completed: false
      })

    if (profileError) throw profileError

    // Create MediaID entry with default privacy settings
    const { error: mediaIdError } = await supabaseClient
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
      const { error: artistError } = await supabaseClient
        .from('artists')
        .insert({
          user_id: userId,
          artist_name: userData.display_name,
          verification_status: 'pending'
        })
      if (artistError) throw artistError
    } else if (userData.role === 'brand') {
      const { error: brandError } = await supabaseClient
        .from('brands')
        .insert({
          user_id: userId,
          brand_name: userData.display_name,
          contact_email: email
        })
      if (brandError) throw brandError
    }

    // Send email verification
    const { error: emailError } = await supabaseClient.auth.admin.generateLink({
      type: 'signup',
      email,
    })

    if (emailError) console.warn('Email verification failed:', emailError)

    return new Response(
      JSON.stringify({
        success: true,
        user: authData.user,
        message: 'Account created successfully. Please check your email for verification.'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 201,
      }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
}) 