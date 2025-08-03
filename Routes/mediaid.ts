import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../middleware/cors.ts'
import { validateRequest } from '../middleware/validation.ts'
import { createErrorResponse, createSuccessResponse, createNotFoundResponse } from '../utils/responses.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''  


export const mediaIdRoutes = {
  // GET /mediaid/preferences
  async getPreferences(req: Request): Promise<Response> {
    try {
      const authHeader = req.headers.get('Authorization')
      if (!authHeader) throw new Error('No authorization header')

      const supabase = createClient(supabaseUrl, supabaseServiceKey, {
        global: { headers: { Authorization: authHeader } }
      })

      const { data: { user }, error: userError } = await supabase.auth.getUser()
      if (userError || !user) throw new Error('Invalid user session')

      const { data: mediaId, error } = await supabase
        .from('media_ids')
        .select('*')
        .eq('user_uuid', user.id)
        .single()

      if (error || !mediaId) {
        return createNotFoundResponse('MediaID')
      }

      return createSuccessResponse({
        mediaId: {
          id: mediaId.id,
          interests: mediaId.interests,
          genre_preferences: mediaId.genre_preferences,
          content_flags: mediaId.content_flags,
          location_code: mediaId.location_code,
          privacy_settings: mediaId.privacy_settings,
          updated_at: mediaId.updated_at
        }
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // PUT /mediaid/preferences
  async updatePreferences(req: Request): Promise<Response> {
    try {
      const authHeader = req.headers.get('Authorization')
      if (!authHeader) throw new Error('No authorization header')

      const updates = await validateRequest(req, {
        interests: 'array',
        privacy_settings: 'object'
      })

      // Validate interests count (3-5 required)
      if (updates.interests.length < 3 || updates.interests.length > 5) {
        throw new Error('Please select 3-5 interests')
      }

      const supabase = createClient(supabaseUrl, supabaseServiceKey, {
        global: { headers: { Authorization: authHeader } }
      })

      const { data: { user }, error: userError } = await supabase.auth.getUser()
      if (userError || !user) throw new Error('Invalid user session')

      const { data: mediaId, error: updateError } = await supabase
        .from('media_ids')
        .update({
          interests: updates.interests,
          genre_preferences: updates.genre_preferences || [],
          content_flags: updates.content_flags || {},
          location_code: updates.location_code,
          privacy_settings: updates.privacy_settings,
          updated_at: new Date().toISOString()
        })
        .eq('user_uuid', user.id)
        .select()
        .single()

      if (updateError) throw updateError

      // Log the update (respecting privacy settings)
      if (updates.privacy_settings.anonymous_logging !== false) {
        await supabase
          .from('media_engagement_log')
          .insert({
            user_id: user.id,
            event_type: 'mediaid_preferences_updated',
            is_anonymous: updates.privacy_settings.anonymous_logging,
            metadata: {
              interests_count: updates.interests.length,
              privacy_level: Object.values(updates.privacy_settings).filter(Boolean).length
            }
          })
      }

      return createSuccessResponse({
        mediaId: {
          id: mediaId.id,
          interests: mediaId.interests,
          genre_preferences: mediaId.genre_preferences,
          content_flags: mediaId.content_flags,
          location_code: mediaId.location_code,
          privacy_settings: mediaId.privacy_settings,
          updated_at: mediaId.updated_at
        },
        message: 'Preferences updated successfully'
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // GET /mediaid/analytics
  async getAnalytics(req: Request): Promise<Response> {
    try {
      const authHeader = req.headers.get('Authorization')
      if (!authHeader) throw new Error('No authorization header')

      const supabase = createClient(supabaseUrl, supabaseServiceKey, {
        global: { headers: { Authorization: authHeader } }
      })

      const { data: { user }, error: userError } = await supabase.auth.getUser()
      if (userError || !user) throw new Error('Invalid user session')

      // Get user's engagement statistics
      const { data: engagementStats, error: statsError } = await supabase
        .from('media_engagement_log')
        .select('event_type, timestamp')
        .eq('user_id', user.id)
        .eq('is_anonymous', false)
        .order('timestamp', { ascending: false })
        .limit(100)

      if (statsError) throw statsError

      // Aggregate data by event type
      const eventCounts = engagementStats.reduce((acc: any, event: any) => {
        acc[event.event_type] = (acc[event.event_type] || 0) + 1
        return acc
      }, {})

      // Get recent activity (last 30 days)
      const thirtyDaysAgo = new Date()
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)

      const recentActivity = engagementStats.filter((event: any) => 
        new Date(event.timestamp) > thirtyDaysAgo
      )

      return createSuccessResponse({
        analytics: {
          totalEvents: engagementStats.length,
          eventBreakdown: eventCounts,
          recentActivityCount: recentActivity.length,
          lastActivity: engagementStats[0]?.timestamp || null
        }
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // POST /mediaid/events
  async logEvent(req: Request): Promise<Response> {
    try {
      const authHeader = req.headers.get('Authorization')

      const { event_type, content_id, metadata, is_anonymous } = await validateRequest(req, {
        event_type: 'string',
        content_id: 'string',
        metadata: 'object',
        is_anonymous: 'boolean'
      })

      const supabase = createClient(supabaseUrl, supabaseServiceKey)

      let userId = null
      if (authHeader && !is_anonymous) {
        const { data: { user } } = await supabase.auth.getUser(authHeader)
        userId = user?.id || null
      }

      // Get user agent and IP for analytics
      const userAgent = req.headers.get('User-Agent') || ''
      const forwardedFor = req.headers.get('X-Forwarded-For')
      const realIp = req.headers.get('X-Real-IP')
      const ipAddress = forwardedFor?.split(',')[0] || realIp || 'unknown'

      await supabase
        .from('media_engagement_log')
        .insert({
          user_id: userId,
          content_id: content_id || null,
          event_type,
          user_agent: userAgent,
          ip_address: ipAddress,
          is_anonymous,
          metadata,
          timestamp: new Date().toISOString()
        })

      return createSuccessResponse({
        message: 'Event logged successfully'
      }, 201)

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // DELETE /mediaid/data
  async deleteUserData(req: Request): Promise<Response> {
    try {
      const authHeader = req.headers.get('Authorization')
      if (!authHeader) throw new Error('No authorization header')

      const supabase = createClient(supabaseUrl, supabaseServiceKey, {
        global: { headers: { Authorization: authHeader } }
      })

      const { data: { user }, error: userError } = await supabase.auth.getUser()
      if (userError || !user) throw new Error('Invalid user session')

      // Delete all user's MediaID data (GDPR compliance)
      const { error: deleteMediaIdError } = await supabase
        .from('media_ids')
        .delete()
        .eq('user_uuid', user.id)

      if (deleteMediaIdError) throw deleteMediaIdError

      // Delete engagement logs
      const { error: deleteLogsError } = await supabase
        .from('media_engagement_log')
        .delete()
        .eq('user_id', user.id)

      if (deleteLogsError) throw deleteLogsError

      return createSuccessResponse({
        message: 'All MediaID data has been deleted successfully'
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  }
} 