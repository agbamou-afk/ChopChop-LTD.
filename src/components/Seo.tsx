import { useEffect } from "react";

interface SeoProps {
  title: string;
  description: string;
  canonical?: string;
  ogType?: "website" | "article";
  jsonLd?: object | object[];
}

function setMeta(attr: "name" | "property", key: string, content: string) {
  let el = document.head.querySelector<HTMLMetaElement>(`meta[${attr}="${key}"]`);
  if (!el) {
    el = document.createElement("meta");
    el.setAttribute(attr, key);
    document.head.appendChild(el);
  }
  el.setAttribute("content", content);
}

function setLink(rel: string, href: string) {
  let el = document.head.querySelector<HTMLLinkElement>(`link[rel="${rel}"]`);
  if (!el) {
    el = document.createElement("link");
    el.setAttribute("rel", rel);
    document.head.appendChild(el);
  }
  el.setAttribute("href", href);
}

export function Seo({ title, description, canonical, ogType = "website", jsonLd }: SeoProps) {
  useEffect(() => {
    document.title = title;
    setMeta("name", "description", description);
    setMeta("property", "og:title", title);
    setMeta("property", "og:description", description);
    setMeta("property", "og:type", ogType);

    const path = canonical ?? window.location.pathname;
    const url = `${window.location.origin}${path}`;
    setMeta("property", "og:url", url);
    setLink("canonical", url);

    let scriptEl: HTMLScriptElement | null = null;
    if (jsonLd) {
      scriptEl = document.createElement("script");
      scriptEl.type = "application/ld+json";
      scriptEl.dataset.seo = "route";
      scriptEl.text = JSON.stringify(jsonLd);
      document.head.appendChild(scriptEl);
    }
    return () => {
      if (scriptEl) scriptEl.remove();
    };
  }, [title, description, canonical, ogType, JSON.stringify(jsonLd)]);

  return null;
}