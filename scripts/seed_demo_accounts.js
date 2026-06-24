/**
 * MICHWAR — Create Demo Accounts (firebase-admin v12+ compatible)
 *
 * HOW TO RUN:
 *   1. Firebase Console → Project Settings → Service Accounts
 *      → Generate new private key → save as "serviceAccountKey.json"
 *      in THIS folder (scripts/)
 *   2. cd scripts && node seed_demo_accounts.js
 */

const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth }              = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const path = require('path');
const fs   = require('fs');

// ── Init ─────────────────────────────────────────────────────────────────────

const keyPath = path.join(__dirname, 'serviceAccountKey.json');

if (!fs.existsSync(keyPath)) {
  console.error('\n❌  serviceAccountKey.json not found in scripts/ folder.');
  console.error('   1. https://console.firebase.google.com/project/michwar-bfcca/settings/serviceaccounts/adminsdk');
  console.error('   2. Generate new private key → rename → place here\n');
  process.exit(1);
}

initializeApp({ credential: cert(require(keyPath)) });

const auth = getAuth();
const db   = getFirestore();

// ── Demo account definitions ──────────────────────────────────────────────────

const DEMO_ACCOUNTS = [
  { email: 'demo.passenger@michwar.dz', password: 'Demo@1234', fullName: 'Demo Passenger', role: 'passenger' },
  { email: 'demo.driver@michwar.dz',    password: 'Demo@1234', fullName: 'Demo Driver',    role: 'driver'    },
  { email: 'demo.admin@michwar.dz',     password: 'Demo@1234', fullName: 'Demo Admin',     role: 'admin'     },
];

// ── Seed ──────────────────────────────────────────────────────────────────────

async function seed() {
  console.log('\n🌱  Seeding MICHWAR demo accounts...\n');

  for (const account of DEMO_ACCOUNTS) {
    let uid;

    try {
      const existing = await auth.getUserByEmail(account.email);
      uid = existing.uid;
      console.log(`   ✓ [exists]  ${account.email}  (${uid})`);
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        const user = await auth.createUser({
          email: account.email,
          password: account.password,
          displayName: account.fullName,
          emailVerified: true,
        });
        uid = user.uid;
        console.log(`   ✓ [created] ${account.email}  (${uid})`);
      } else {
        console.error(`   ✗ ${account.email}: ${e.message}`);
        continue;
      }
    }

    await db.collection('users').doc(uid).set({
      uid,
      email:        account.email,
      fullName:     account.fullName,
      role:         account.role,
      roleSelected: true,
      phoneNumber:  '',
      avatar:       '',
      loyalty:      { points: 0, tier: 'standard', totalRides: 0 },
      createdAt:    FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log(`   ✓ [firestore] users/${uid}`);

    if (account.role === 'driver') {
      await db.collection('drivers').doc(uid).set({
        userId:             uid,
        isOnline:           false,
        isOnTrip:           false,
        verificationStatus: 'approved',
        vehicleCategory:    'standard',
        rating:             4.8,
        totalRides:         0,
        commissionTier:     'standard',
        documentsMeta:      {},
        createdAt:          FieldValue.serverTimestamp(),
      }, { merge: true });
      console.log(`   ✓ [firestore] drivers/${uid}`);

      await db.collection('wallets').doc(uid).set({
        driverId:      uid,
        balanceDzd:    0,
        totalEarned:   0,
        totalDeducted: 0,
        createdAt:     FieldValue.serverTimestamp(),
      }, { merge: true });
      console.log(`   ✓ [firestore] wallets/${uid}`);
    }

    console.log('');
  }

  console.log('✅  Done!\n');
  console.log('   Passenger → demo.passenger@michwar.dz / Demo@1234');
  console.log('   Driver    → demo.driver@michwar.dz    / Demo@1234');
  console.log('   Admin     → demo.admin@michwar.dz     / Demo@1234\n');
  process.exit(0);
}

seed().catch(err => {
  console.error('\n❌  Seed failed:', err.message);
  process.exit(1);
});
