import i18n from '@ohos.i18n';

// Whether the app's language reads right to left, so start is right. A
// `.direction()` on an ancestor doesn't change it.
export function isRtl(): boolean {
  return i18n.isRTL(i18n.System.getAppPreferredLanguage());
}
