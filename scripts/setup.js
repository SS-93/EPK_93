#!/usr/bin/env node

const { exec } = require('child_process')
const fs = require('fs')
const path = require('path')

console.log('🚀 Setting up Bucket & MediaID Backend...\n')

// Check if .env file exists
const envPath = path.join(__dirname, '..', '.env')
if (!fs.existsSync(envPath)) {
  console.log('⚠️  No .env file found. Creating from example...')
  const examplePath = path.join(__dirname, '..', 'env.example')
  if (fs.existsSync(examplePath)) {
    fs.copyFileSync(examplePath, envPath)
    console.log('✅ Created .env file from example')
    console.log('📝 Please edit .env with your actual credentials\n')
  }
}

// Load environment variables
require('dotenv').config({ path: envPath })

const DATABASE_URL = process.env.DATABASE_URL

if (!DATABASE_URL) {
  console.error('❌ DATABASE_URL not found in .env file')
  console.log('Please add your database URL to the .env file:')
  console.log('DATABASE_URL=postgresql://user:password@host:port/database')
  process.exit(1)
}

console.log('🔗 Database URL configured')

// Function to run shell commands
const runCommand = (command, description) => {
  return new Promise((resolve, reject) => {
    console.log(`🔄 ${description}...`)
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`❌ ${description} failed:`, error.message)
        reject(error)
        return
      }
      if (stderr) {
        console.warn(`⚠️  ${description} warnings:`, stderr)
      }
      if (stdout) {
        console.log(stdout)
      }
      console.log(`✅ ${description} completed`)
      resolve(stdout)
    })
  })
}

// Setup sequence
async function setup() {
  try {
    // 1. Install dependencies
    await runCommand('npm install', 'Installing dependencies')
    
    // 2. Check Supabase CLI
    try {
      await runCommand('supabase --version', 'Checking Supabase CLI')
    } catch (error) {
      console.log('📦 Installing Supabase CLI...')
      await runCommand('npm install -g supabase', 'Installing Supabase CLI globally')
    }
    
    // 3. Initialize Supabase (if not already done)
    if (!fs.existsSync(path.join(__dirname, '..', 'supabase'))) {
      await runCommand('supabase init', 'Initializing Supabase project')
    } else {
      console.log('✅ Supabase already initialized')
    }
    
    // 4. Start local Supabase (this will use your remote DB if configured)
    console.log('🔄 Starting Supabase services...')
    console.log('This will start local development environment')
    console.log('If you want to use your remote database, configure supabase/config.toml\n')
    
    // 5. Apply migrations
    console.log('📋 Ready to apply database migrations')
    console.log('Run the following commands:')
    console.log('  npm run dev          # Start Supabase locally')
    console.log('  npm run db:migrate   # Apply database schema')
    console.log('  npm run type-gen     # Generate TypeScript types')
    
    console.log('\n🎉 Backend setup complete!')
    console.log('\n📖 Next steps:')
    console.log('1. Update supabase/config.toml with your remote database settings')
    console.log('2. Run npm run dev to start development environment')
    console.log('3. Run npm run db:migrate to apply database schema')
    console.log('4. Configure OAuth providers in Supabase dashboard')
    
  } catch (error) {
    console.error('❌ Setup failed:', error.message)
    process.exit(1)
  }
}

setup() 