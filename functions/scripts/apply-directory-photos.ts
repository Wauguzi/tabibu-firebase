#!/usr/bin/env npx ts-node
/**
 * Brings the live demo directory in line with `data/demo_directory.json` without reseeding it:
 * a photo where the account has none (or where `--replace=<key,...>` names the entry), and the
 * entry's name where it differs. Only accounts the seed created are touched (the `seeded` claim);
 * anyone else's sign-up is refused. Photos are copied into Storage, as the profile rules require.
 * Dry by default; `--live` needs the same confirm guard as the seed scripts.
 *
 * Usage:
 *   SEED_EMAIL_TEMPLATE='tabibu.demo+{role}@gmail.com' npx ts-node scripts/apply-directory-photos.ts
 *   ... --replace=wambui-lucy --live    # needs SEED_CONFIRM=tabibu-86ea2
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { getApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

import { syncPractitionerHandler } from '../src/identity';
import { PROJECT, storeDemoPhoto } from '../src/seed';

interface Entry {
  key: string;
  firstName: string;
  lastName: string;
  photo: { url: string; source: string; author: string; licence: string } | null;
}

const LIVE = process.argv.includes('--live');
const REPLACE = new Set(
  (process.argv.find((a) => a.startsWith('--replace='))?.slice('--replace='.length) ?? '')
    .split(',')
    .filter((k) => k !== ''),
);
const PHOTO_HOSTS = ['images.pexels.com', 'images.unsplash.com'];

async function main(): Promise<void> {
  if (LIVE && process.env.SEED_CONFIRM !== PROJECT) {
    throw new Error(`Changing the live directory needs SEED_CONFIRM=${PROJECT}.`);
  }
  const template = process.env.SEED_EMAIL_TEMPLATE ?? '';
  if (!template.includes('{role}')) throw new Error("SEED_EMAIL_TEMPLATE is needed, e.g. 'tabibu.demo+{role}@gmail.com'.");
  const entries = (
    JSON.parse(readFileSync(join(__dirname, '../data/demo_directory.json'), 'utf8')) as { practitioners: Entry[] }
  ).practitioners;
  for (const key of REPLACE) {
    if (!entries.some((e) => e.key === key)) throw new Error(`--replace names an unknown entry: ${key}`);
  }
  try {
    getApp();
  } catch {
    initializeApp({ projectId: PROJECT, storageBucket: `${PROJECT}.firebasestorage.app` });
  }
  const db = getFirestore();
  const bucket = getStorage().bucket().name;

  const plan: { key: string; uid: string; photo?: string; name?: string }[] = [];
  for (const entry of entries) {
    const email = template.replace('{role}', `directory-${entry.key}`).toLowerCase();
    let user;
    try {
      user = await getAuth().getUserByEmail(email);
    } catch {
      continue; // Not seeded on this project.
    }
    if (user.customClaims?.seeded !== true) {
      throw new Error(`${entry.key}: ${user.uid} was not created by the seed; refusing to change it.`);
    }
    const doc = (await db.collection('doctors').doc(user.uid).get()).data() ?? {};
    const step: (typeof plan)[number] = { key: entry.key, uid: user.uid };
    const photo = entry.photo;
    if (photo !== null && (doc.profilePictureUrl === '' || REPLACE.has(entry.key))) {
      const url = new URL(photo.url);
      if (url.protocol !== 'https:' || !PHOTO_HOSTS.includes(url.hostname)) {
        throw new Error(`${entry.key}: photos come from ${PHOTO_HOSTS.join(' or ')} over https.`);
      }
      step.photo = photo.url;
    }
    if (doc.firstName !== entry.firstName || doc.lastName !== entry.lastName) {
      step.name = `${doc.firstName} ${doc.lastName} -> ${entry.firstName} ${entry.lastName}`;
    }
    if (step.photo || step.name) plan.push(step);
  }
  console.log(JSON.stringify({ project: PROJECT, live: LIVE, plan }, null, 2));
  if (!LIVE) {
    console.log(`Dry run: ${plan.length} account(s) would change. Pass --live with SEED_CONFIRM set to apply.`);
    return;
  }

  let done = 0;
  for (const step of plan) {
    // One failure must not stop the rest; it is reported and that account stays as it was.
    try {
      const entry = entries.find((e) => e.key === step.key)!;
      const update: Record<string, string> = { lastUpdatedAt: new Date().toISOString() };
      if (step.photo) update.profilePictureUrl = await storeDemoPhoto(step.photo, step.uid, bucket);
      if (step.name) {
        update.firstName = entry.firstName;
        update.lastName = entry.lastName;
      }
      await db.collection('doctors').doc(step.uid).update(update);
      await syncPractitionerHandler(db, step.uid);
      done += 1;
      console.log(`Updated ${step.key}`);
    } catch (error) {
      console.error(`Kept ${step.key}: ${(error as Error).message}`);
      process.exitCode = 1;
    }
  }
  console.log(`Updated ${done} of ${plan.length}.`);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
