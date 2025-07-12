#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const postgres = require('postgres')

// Load environment variables
require('dotenv').config()

const DATABASE_URL = process.env.DATABASE_URL

if (!DATABASE_URL) {
  console.error('❌ DATABASE_URL not found in environment variables')
  process.exit(1)
}

console.log('🔗 Connecting to database...')

const sql = postgres(DATABASE_URL, {
  host_ssl: 'prefer',
  ssl: { rejectUnauthorized: false }
})

async function runMigrations() {
  try {
    console.log('🔄 Starting database migrations...\n')

    // Create migrations table if it doesn't exist
    await sql`
      CREATE TABLE IF NOT EXISTS migrations (
        id SERIAL PRIMARY KEY,
        filename VARCHAR(255) NOT NULL UNIQUE,
        applied_at TIMESTAMP DEFAULT NOW()
      )
    `
    
    // Get list of applied migrations
    const appliedMigrations = await sql`
      SELECT filename FROM migrations ORDER BY applied_at
    `
    const appliedList = appliedMigrations.map(m => m.filename)
    
    // Get list of migration files
    const migrationsDir = path.join(__dirname, '..', 'database', 'migrations')
    
    if (!fs.existsSync(migrationsDir)) {
      console.error('❌ Migrations directory not found:', migrationsDir)
      process.exit(1)
    }
    
    const migrationFiles = fs.readdirSync(migrationsDir)
      .filter(file => file.endsWith('.sql'))
      .sort()
    
    console.log(`📋 Found ${migrationFiles.length} migration files`)
    console.log(`✅ ${appliedList.length} migrations already applied\n`)
    
    // Apply pending migrations
    for (const filename of migrationFiles) {
      if (appliedList.includes(filename)) {
        console.log(`⏭️  Skipping ${filename} (already applied)`)
        continue
      }
      
      console.log(`🔄 Applying migration: ${filename}`)
      
      const filePath = path.join(migrationsDir, filename)
      const migrationSQL = fs.readFileSync(filePath, 'utf8')
      
      try {
        // Execute the migration
        await sql.unsafe(migrationSQL)
        
        // Record the migration as applied
        await sql`
          INSERT INTO migrations (filename) VALUES (${filename})
        `
        
        console.log(`✅ Successfully applied: ${filename}`)
      } catch (error) {
        console.error(`❌ Failed to apply migration ${filename}:`, error.message)
        throw error
      }
    }
    
    console.log('\n🎉 All migrations completed successfully!')
    
    // Verify core tables exist
    console.log('\n🔍 Verifying database schema...')
    
    const coreTablese = ['profiles', 'media_ids', 'artists', 'subscriptions']
    for (const table of coreTablese) {
      const exists = await sql`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' 
          AND table_name = ${table}
        )
      `
      
      if (exists[0].exists) {
        console.log(`✅ Table '${table}' exists`)
      } else {
        console.log(`❌ Table '${table}' missing`)
      }
    }
    
    console.log('\n🏁 Database migration complete!')
    
  } catch (error) {
    console.error('❌ Migration failed:', error)
    process.exit(1)
  } finally {
    await sql.end()
  }
}

runMigrations() 