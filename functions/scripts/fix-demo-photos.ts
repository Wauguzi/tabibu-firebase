#!/usr/bin/env npx ts-node
/**
 * Moves profile photos that point outside Storage (stock links set by hand or by an older seed)
 * into `profilePictures/{uid}/`, so the owner can save their profile again: the profile rules
 * accept only the project's own download URL, on every save. Patients and doctors (which holds
 * pathologists too). Dry by default; `--live` needs the same confirm guard as the seed scripts.
 *
 * Usage:
 *   npx ts-node scripts/fix-demo-photos.ts           # lists what would move
 *   npx ts-node scripts/fix-demo-photos.ts --live    # needs SEED_CONFIRM=tabibu-86ea2
 */
import { getApp, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

import { syncPractitionerHandler } from '../src/identity';
import { isProfileStorageUrl, PROJECT, storeDemoPhoto } from '../src/seed';

const LIVE = process.argv.includes('--live');
const COLLECTIONS = ['patients', 'doctors'] as const;

async function main(): Promise<void> {
  if (LIVE && process.env.SEED_CONFIRM !== PROJECT) {
    throw new Error(`Moving photos in the live project needs SEED_CONFIRM=${PROJECT}.`);
  }
  try {
    getApp();
  } catch {
    initializeApp({ projectId: PROJECT, storageBucket: `${PROJECT}.firebasestorage.app` });
  }
  const db = getFirestore();
  const bucket = getStorage().bucket().name;

  const moves: { collection: (typeof COLLECTIONS)[number]; uid: string; url: string }[] = [];
  for (const collection of COLLECTIONS) {
    const docs = await db.collection(collection).get();
    for (const doc of docs.docs) {
      const url = doc.get('profilePictureUrl');
      if (typeof url !== 'string' || url === '' || isProfileStorageUrl(url, doc.id)) continue;
      moves.push({ collection, uid: doc.id, url });
    }
  }
  console.log(JSON.stringify({ project: PROJECT, live: LIVE, moves }, null, 2));
  if (!LIVE) {
    console.log(`Dry run: ${moves.length} photo(s) would move. Pass --live with SEED_CONFIRM set to apply.`);
    return;
  }

  let moved = 0;
  for (const move of moves) {
    // One failure must not stop the rest; it is reported and the photo stays as it was.
    try {
      const stored = await storeDemoPhoto(move.url, move.uid, bucket);
      await db
        .collection(move.collection)
        .doc(move.uid)
        .update({ profilePictureUrl: stored, lastUpdatedAt: new Date().toISOString() });
      if (move.collection === 'doctors') await syncPractitionerHandler(db, move.uid);
      moved += 1;
      console.log(`Moved ${move.collection}/${move.uid}`);
    } catch (error) {
      console.error(`Kept ${move.collection}/${move.uid}: ${(error as Error).message}`);
      process.exitCode = 1;
    }
  }
  console.log(`Moved ${moved} of ${moves.length}.`);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
