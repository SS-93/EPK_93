import { createClient, SupabaseClient } from '@supabase/supabase-js'
import postgres from 'postgres'

// Environment variables
const DATABASE_URL = process.env.DATABASE_URL || ''
const SUPABASE_URL = process.env.SUPABASE_URL || ''
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || ''
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || ''

// Direct PostgreSQL connection for advanced queries
export const sql = postgres(DATABASE_URL, {
  host_ssl: 'prefer',
  ssl: { rejectUnauthorized: false },
  max: 10,
  idle_timeout: 20,
  connect_timeout: 10,
})

// Supabase client for standard operations
export const supabaseAdmin: SupabaseClient = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  }
)

// Public Supabase client (for client-side operations)
export const supabaseClient: SupabaseClient = createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
)

// Database health check
export const checkDatabaseConnection = async (): Promise<boolean> => {
  try {
    const result = await sql`SELECT 1 as health_check`
    console.log('✅ Database connection successful:', result[0])
    return true
  } catch (error) {
    console.error('❌ Database connection failed:', error)
    return false
  }
}

// Run migrations
export const runMigrations = async (): Promise<void> => {
  try {
    console.log('🔄 Running database migrations...')
    
    // Check if tables exist, if not run initial schema
    const tablesExist = await sql`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'profiles'
      );
    `
    
    if (!tablesExist[0].exists) {
      console.log('📋 Creating initial schema...')
      // Here you would run your migration files
      // For now, we'll just log that migrations need to be run manually
      console.log('⚠️  Please run: npm run db:migrate to apply schema')
    } else {
      console.log('✅ Database schema already exists')
    }
  } catch (error) {
    console.error('❌ Migration error:', error)
    throw error
  }
}

// Initialize database
export const initializeDatabase = async (): Promise<void> => {
  await checkDatabaseConnection()
  await runMigrations()
}

// Close database connection
export const closeDatabaseConnection = async (): Promise<void> => {
  await sql.end()
} 