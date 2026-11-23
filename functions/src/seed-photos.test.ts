import assert from 'node:assert/strict';

import { getStorage } from 'firebase-admin/storage';

import { BUCKET, emulatorDeps, resetEmulators } from './emulator.test-support';
import { isProfileStorageUrl, storeDemoPhoto } from './seed';

const STOCK = 'https://images.pexels.com/photos/15520551/pexels-photo-15520551.jpeg?w=512';
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);

function photoFetch(body: Buffer, type: string, status = 200): typeof fetch {
  return (async () =>
    new Response(new Uint8Array(body), { status, headers: { 'content-type': type } })) as typeof fetch;
}

describe('demo photos', () => {
  describe('isProfileStorageUrl', () => {
    const own = (bucket: string, uid: string) =>
      `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/profilePictures%2F${uid}%2Fphoto.jpg?alt=media&token=t`;

    it('accepts the project bucket and the emulator bucket, for the owner only', () => {
      assert.equal(isProfileStorageUrl(own('tabibu-86ea2.firebasestorage.app', 'u1'), 'u1'), true);
      assert.equal(isProfileStorageUrl(own('demo-tabibu.appspot.com', 'u1'), 'u1'), true);
      assert.equal(isProfileStorageUrl(own('tabibu-86ea2.firebasestorage.app', 'u1'), 'u2'), false);
    });

    it('refuses a stock link, another bucket and another folder', () => {
      assert.equal(isProfileStorageUrl(STOCK, 'u1'), false);
      assert.equal(isProfileStorageUrl(own('someone-else.appspot.com', 'u1'), 'u1'), false);
      assert.equal(
        isProfileStorageUrl(
          'https://firebasestorage.googleapis.com/v0/b/tabibu-86ea2.firebasestorage.app/o/licenses%2Fu1%2Fa.pdf?alt=media',
          'u1',
        ),
        false,
      );
    });
  });

  describe('storeDemoPhoto', () => {
    beforeEach(resetEmulators);

    it('stores the photo under profilePictures/{uid}/ and returns a URL the rules accept', async () => {
      emulatorDeps();
      const url = await storeDemoPhoto(STOCK, 'patient-1', BUCKET, photoFetch(JPEG, 'image/jpeg'));

      assert.equal(isProfileStorageUrl(url, 'patient-1'), true);
      const [saved] = await getStorage().bucket(BUCKET).file('profilePictures/patient-1/photo.jpg').download();
      assert.deepEqual(saved, JPEG);
    });

    it('refuses a failed download, a non-image and an empty body, storing nothing', async () => {
      emulatorDeps();
      await assert.rejects(storeDemoPhoto(STOCK, 'p', BUCKET, photoFetch(JPEG, 'image/jpeg', 404)), /404/);
      await assert.rejects(storeDemoPhoto(STOCK, 'p', BUCKET, photoFetch(JPEG, 'text/html')), /not a JPEG or PNG/);
      await assert.rejects(storeDemoPhoto(STOCK, 'p', BUCKET, photoFetch(Buffer.alloc(0), 'image/jpeg')), /0 bytes/);
      const [exists] = await getStorage().bucket(BUCKET).file('profilePictures/p/photo.jpg').exists();
      assert.equal(exists, false);
    });
  });
});
