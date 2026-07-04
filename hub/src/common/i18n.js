'use strict';

const fs = require('fs');
const path = require('path');

const LOCALES_DIR = path.join(__dirname, '..', '..', 'locales');
const DEFAULT_LOCALE = 'en';

let currentLocale = DEFAULT_LOCALE;
let translations = {};
let fallbackTranslations = {};
let availableLocales = [];

function loadLocaleList() {
  try {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(LOCALES_DIR, 'manifest.json'), 'utf-8')
    );
    availableLocales = manifest.locales || [];
  } catch {
    availableLocales = [{ code: 'en', name: 'English', nativeName: 'English' }];
  }
  return availableLocales;
}

function loadTranslations(locale) {
  const filePath = path.join(LOCALES_DIR, `${locale}.json`);
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  } catch {
    return {};
  }
}

function init(locale) {
  loadLocaleList();
  fallbackTranslations = loadTranslations(DEFAULT_LOCALE);
  setLocale(locale || detectSystemLocale());
}

function detectSystemLocale() {
  const env = process.env.LANG || process.env.LC_ALL || process.env.LC_MESSAGES || '';
  const match = env.match(/^([a-z]{2,3})(?:_[A-Z]{2})?/);
  if (match && availableLocales.find((l) => l.code === match[1])) {
    return match[1];
  }
  return DEFAULT_LOCALE;
}

function setLocale(locale) {
  const valid = availableLocales.find((l) => l.code === locale);
  if (!valid) locale = DEFAULT_LOCALE;
  currentLocale = locale;
  translations = loadTranslations(locale);
  if (locale !== DEFAULT_LOCALE) {
    fallbackTranslations = loadTranslations(DEFAULT_LOCALE);
  }
}

function loadTranslationsForRenderer(locale) {
  const base = loadTranslations(DEFAULT_LOCALE);
  const target = locale === DEFAULT_LOCALE ? base : loadTranslations(locale);
  return { ...base, ...target };
}

function t(key, params) {
  let text = translations[key] || fallbackTranslations[key] || key;
  if (params) {
    Object.entries(params).forEach(([k, v]) => {
      text = text.replace(new RegExp(`\\{${k}\\}`, 'g'), v);
    });
  }
  return text;
}

function getLocale() {
  return currentLocale;
}

function getAvailableLocales() {
  return availableLocales;
}

module.exports = {
  init,
  setLocale,
  getLocale,
  getAvailableLocales,
  t,
  detectSystemLocale,
  loadTranslationsForRenderer,
};
