import { serve } from "https://deno.land/std@0.208.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// OCR/NER Extraction Logic (adapted from frontend)
interface ExtractionResult {
  metadata: Record<string, any>
  confidence: Record<string, number>
  errors: string[]
}

// Country code mapping
const COUNTRY_NAME_TO_ISO: Record<string, string> = {
  'united states': 'US', 'usa': 'US', 'america': 'US',
  'united kingdom': 'GB', 'uk': 'GB', 'britain': 'GB',
  'canada': 'CA', 'australia': 'AU', 'germany': 'DE',
  'france': 'FR', 'japan': 'JP', 'south korea': 'KR',
  'brazil': 'BR', 'mexico': 'MX', 'spain': 'ES',
  'italy': 'IT', 'netherlands': 'NL', 'sweden': 'SE',
  'norway': 'NO', 'denmark': 'DK', 'finland': 'FI'
}

// Regex patterns for extraction
const PATTERNS = {
  URL: /https?:\/\/[^\s]+/g,
  DATE: /\b(\d{1,2})\/(\d{1,2})\/(\d{2,4})\b/g,
  ISRC: /\b[A-Z]{2}[A-Z0-9]{3}\d{7}\b/g,
  EMAIL: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/g
}

// License type detection
const LICENSE_KEYWORDS = {
  'all_rights_reserved': ['all rights reserved', 'copyright', '©'],
  'cc_by': ['creative commons by', 'cc by', 'attribution'],
  'cc_by_sa': ['creative commons by-sa', 'cc by-sa', 'sharealike'],
  'cc_by_nc': ['creative commons by-nc', 'cc by-nc', 'non-commercial'],
  'cc_by_nc_sa': ['creative commons by-nc-sa', 'cc by-nc-sa'],
  'cc_by_nd': ['creative commons by-nd', 'cc by-nd', 'no derivatives'],
  'cc_by_nc_nd': ['creative commons by-nc-nd', 'cc by-nc-nd'],
  'bsl': ['buckets sync library', 'bsl', 'music supervision']
}

// Boolean keyword detection
const BOOLEAN_KEYWORDS = {
  explicit: ['explicit', 'explicit content', 'contains explicit', 'parental advisory'],
  enable_direct_downloads: ['direct download', 'download', 'downloadable'],
  offline_listening: ['offline', 'offline listening', 'offline playback'],
  include_in_rss: ['rss', 'feed', 'rss feed'],
  display_embed_code: ['embed', 'embed code', 'embeddable'],
  enable_app_playback: ['app playback', 'external apps', 'third party'],
  allow_comments: ['comments', 'allow comments', 'commenting'],
  show_comments_public: ['public comments', 'show comments'],
  show_insights_public: ['public insights', 'show insights', 'analytics public']
}

class MetadataExtractor {
  static extractFromText(ocrText: string): ExtractionResult {
    const text = ocrText.toLowerCase().trim()
    const result: ExtractionResult = {
      metadata: {},
      confidence: {},
      errors: []
    }

    try {
      // Extract URLs
      const urls = this.extractUrls(ocrText)
      if (urls.length > 0) {
        result.metadata.buy_link_url = urls[0]
        result.confidence.buy_link_url = 0.8
      }

      // Extract dates
      const dates = this.extractDates(ocrText)
      if (dates.length > 0) {
        result.metadata.release_date = dates[0]
        result.confidence.release_date = 0.7
      }

      // Extract ISRC
      const isrcCodes = this.extractISRC(ocrText)
      if (isrcCodes.length > 0) {
        result.metadata.isrc = isrcCodes[0]
        result.confidence.isrc = 0.9
      }

      // Extract boolean flags
      const booleanFlags = this.extractBooleanFlags(text)
      Object.assign(result.metadata, booleanFlags.metadata)
      Object.assign(result.confidence, booleanFlags.confidence)

      // Extract license information
      const license = this.extractLicense(text)
      if (license) {
        result.metadata.license_type = license.type
        result.confidence.license_type = license.confidence
      }

      // Extract regions/countries
      const regions = this.extractRegions(text)
      if (regions.length > 0) {
        result.metadata.availability_regions = regions
        result.metadata.availability_scope = 'exclusive_regions'
        result.confidence.availability_regions = 0.6
      }

      // Extract organizational info
      const orgInfo = this.extractOrganizationalInfo(ocrText)
      Object.assign(result.metadata, orgInfo.metadata)
      Object.assign(result.confidence, orgInfo.confidence)

    } catch (error) {
      result.errors.push(`Extraction error: ${error}`)
    }

    return result
  }

  private static extractUrls(text: string): string[] {
    const matches = text.match(PATTERNS.URL)
    return matches ? matches.filter(url => this.isValidUrl(url)) : []
  }

  private static extractDates(text: string): string[] {
    const matches = text.match(PATTERNS.DATE)
    if (!matches) return []

    return matches.map(dateStr => {
      const match = dateStr.match(/(\d{1,2})\/(\d{1,2})\/(\d{2,4})/)
      if (!match) return null
      const [, month, day, year] = match

      const fullYear = year.length === 2 ? `20${year}` : year
      const paddedMonth = month.padStart(2, '0')
      const paddedDay = day.padStart(2, '0')
      
      return `${fullYear}-${paddedMonth}-${paddedDay}`
    }).filter(Boolean) as string[]
  }

  private static extractISRC(text: string): string[] {
    const matches = text.toUpperCase().match(PATTERNS.ISRC)
    return matches ? matches.filter(isrc => this.isValidISRC(isrc)) : []
  }

  private static extractBooleanFlags(text: string): {
    metadata: Record<string, any>
    confidence: Record<string, number>
  } {
    const metadata: Record<string, any> = {}
    const confidence: Record<string, number> = {}

    Object.entries(BOOLEAN_KEYWORDS).forEach(([key, keywords]) => {
      const found = keywords.some(keyword => {
        const pattern = new RegExp(`\\b${keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i')
        return pattern.test(text)
      })

      if (found) {
        const negativeWords = ['not', 'disable', 'off', 'false', 'no']
        const hasNegative = negativeWords.some(neg => {
          const negPattern = new RegExp(`${neg}\\s+${keywords[0]}`, 'i')
          return negPattern.test(text)
        })

        metadata[key] = !hasNegative
        confidence[key] = hasNegative ? 0.6 : 0.8
      }
    })

    return { metadata, confidence }
  }

  private static extractLicense(text: string): { type: string, confidence: number } | null {
    for (const [licenseType, keywords] of Object.entries(LICENSE_KEYWORDS)) {
      for (const keyword of keywords) {
        if (text.includes(keyword)) {
          return {
            type: licenseType,
            confidence: keyword === 'all rights reserved' ? 0.9 : 0.7
          }
        }
      }
    }
    return null
  }

  private static extractRegions(text: string): string[] {
    const regions: Set<string> = new Set()

    Object.entries(COUNTRY_NAME_TO_ISO).forEach(([countryName, isoCode]) => {
      if (text.includes(countryName)) {
        regions.add(isoCode)
      }
    })

    const isoPattern = /\b[A-Z]{2}\b/g
    const isoMatches = text.toUpperCase().match(isoPattern)
    if (isoMatches) {
      isoMatches.forEach(code => {
        if (Object.values(COUNTRY_NAME_TO_ISO).includes(code)) {
          regions.add(code)
        }
      })
    }

    return Array.from(regions).slice(0, 20)
  }

  private static extractOrganizationalInfo(text: string): {
    metadata: Record<string, any>
    confidence: Record<string, number>
  } {
    const metadata: Record<string, any> = {}
    const confidence: Record<string, number> = {}

    const labelPatterns = [
      /record label[:\s]+([^\n\r]+)/i,
      /label[:\s]+([^\n\r]+)/i,
      /released by[:\s]+([^\n\r]+)/i
    ]

    for (const pattern of labelPatterns) {
      const match = text.match(pattern)
      if (match && match[1]) {
        metadata.record_label = match[1].trim()
        confidence.record_label = 0.7
        break
      }
    }

    const publisherPatterns = [
      /publisher[:\s]+([^\n\r]+)/i,
      /published by[:\s]+([^\n\r]+)/i,
      /music publisher[:\s]+([^\n\r]+)/i
    ]

    for (const pattern of publisherPatterns) {
      const match = text.match(pattern)
      if (match && match[1]) {
        metadata.publisher = match[1].trim()
        confidence.publisher = 0.7
        break
      }
    }

    return { metadata, confidence }
  }

  private static isValidUrl(url: string): boolean {
    try {
      new URL(url)
      return true
    } catch {
      return false
    }
  }

  private static isValidISRC(isrc: string): boolean {
    return /^[A-Z]{2}[A-Z0-9]{3}\d{7}$/.test(isrc)
  }
}

// Main Edge Function
serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { file_path, content_item_id, raw_text } = await req.json()
    
    if (!content_item_id || !raw_text) {
      return new Response(
        JSON.stringify({ error: 'Missing content_item_id or raw_text' }),
        { 
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Process text with OCR/NER extraction
    console.log('Processing lyrics text for content:', content_item_id)
    const extractionResult = MetadataExtractor.extractFromText(raw_text)

    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Prepare lyrics data with extraction results
    const lyricsData = {
      text: raw_text,
      synchronized: false,
      language: 'en',
      rights_cleared: false,
      extracted_metadata: extractionResult.metadata,
      confidence_scores: extractionResult.confidence,
      processing_errors: extractionResult.errors,
      processed_at: new Date().toISOString()
    }

    // Update content_items with processed lyrics and any extracted metadata
    const updateData: Record<string, any> = {
      lyrics: lyricsData
    }

    // Apply high-confidence extracted metadata
    Object.entries(extractionResult.metadata).forEach(([key, value]) => {
      const confidence = extractionResult.confidence[key] || 0
      if (confidence >= 0.7 && value !== undefined) {
        updateData[key] = value
      }
    })

    const { data, error } = await supabase
      .from('content_items')
      .update(updateData)
      .eq('id', content_item_id)
      .select()
      .single()

    if (error) {
      console.error('Database error:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { 
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log('Successfully processed lyrics for content:', content_item_id)

    return new Response(
      JSON.stringify({ 
        success: true, 
        data,
        extraction_summary: {
          metadata_fields_extracted: Object.keys(extractionResult.metadata).length,
          avg_confidence: Object.values(extractionResult.confidence).reduce((a, b) => a + b, 0) / Object.values(extractionResult.confidence).length || 0,
          errors: extractionResult.errors
        }
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Edge function error:', error)
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error',
        details: error.message 
      }),
      { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})