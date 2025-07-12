import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface MediaIDSetupRequest {
  interests: string[]
  genre_preferences: string[]
  location_code?: string
  privacy_settings: {
    data_sharing: boolean
    location_access: boolean
    audio_capture: boolean
    anonymous_logging: boolean
    marketing_communications: boolean
  }
  content_flags?: Record<string, any>
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get user from JWT
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('No authorization header')

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader }
        }
      }
    )

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser()
    if (userError || !user) throw new Error('Invalid user session')

    const mediaIdData: MediaIDSetupRequest = await req.json()

    // Validate interests (3-5 required)
    if (!mediaIdData.interests || mediaIdData.interests.length < 3 || mediaIdData.interests.length > 5) {
      throw new Error('Please select 3-5 interests')
    }

    // Update MediaID with user preferences
    const { error: updateError } = await supabaseClient
      .from('media_ids')
      .update({
        interests: mediaIdData.interests,
        genre_preferences: mediaIdData.genre_preferences || [],
        location_code: mediaIdData.location_code,
        privacy_settings: mediaIdData.privacy_settings,
        content_flags: mediaIdData.content_flags || {},
        updated_at: new Date().toISOString()
      })
      .eq('user_uuid', user.id)

    if (updateError) throw updateError

    // Mark onboarding as completed
    const { error: profileError } = await supabaseClient
      .from('profiles')
      .update({
        onboarding_completed: true,
        updated_at: new Date().toISOString()
      })
      .eq('id', user.id)

    if (profileError) throw profileError

    // Log the setup completion (anonymous)
    await supabaseClient
      .from('media_engagement_log')
      .insert({
        user_id: user.id,
        event_type: 'mediaid_setup_completed',
        is_anonymous: mediaIdData.privacy_settings.anonymous_logging,
        metadata: {
          interests_count: mediaIdData.interests.length,
          privacy_level: Object.values(mediaIdData.privacy_settings).filter(Boolean).length
        }
      })

    return new Response(
      JSON.stringify({
        success: true,
        message: 'MediaID setup completed successfully'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
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