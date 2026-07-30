import { firstHTTPURL } from "@/lib/editor";
import type { PostPlan } from "@/lib/skejTypes";

export const LINK_PREVIEW_DEBOUNCE_MS = 500;

export function automaticLinkPreviewURL(post: PostPlan) {
  const url = firstHTTPURL(post.text);
  if (!url || post.embed?.images?.length || post.embed?.record) return null;
  return url;
}

export function canApplyAutomaticLinkPreview(
  post: PostPlan,
  requestedURL: string,
  replaceExistingExternalURI?: string
) {
  return (
    automaticLinkPreviewURL(post) === requestedURL &&
    !post.embed?.images?.length &&
    !post.embed?.record &&
    (!post.embed?.external ||
      post.embed.external.uri === replaceExistingExternalURI)
  );
}

export function shouldRemoveAutomaticLinkPreview(
  post: PostPlan,
  automaticURL: string | undefined
) {
  return (
    automaticURL !== undefined &&
    firstHTTPURL(post.text) !== automaticURL &&
    post.embed?.external?.uri === automaticURL
  );
}
