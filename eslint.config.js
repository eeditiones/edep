import { defineConfig } from 'eslint/config';
import globals from 'globals';
import js from '@eslint/js';
import html from '@html-eslint/eslint-plugin';
import eslintConfigPrettier from 'eslint-config-prettier';
export default defineConfig([
    { ignores: ['node_modules', 'build'] },
    { files: ['**/*.{js,mjs,cjs}'] },
    { files: ['**/*.{js,mjs,cjs}'], languageOptions: { globals: globals.browser } },
    { files: ['**/*.{js,mjs,cjs}'], plugins: { js } },
    {
        files: ['**/*.html'],
        ...html.configs['flat/recommended'],

        rules: {
            ...html.configs['flat/recommended'].rules, // Must be defined. If not, all recommended rules will be lost
            '@html-eslint/require-closing-tags': ['error', { selfClosing: 'always' }],
            '@html-eslint/require-lang': 'off',
            '@html-eslint/require-img-alt': 'off',

            // Titles are commonly filled from data-template
            '@html-eslint/require-title': 'off',

            // Disable stylistic rules. We have prettier for that
            '@html-eslint/indent': 'off',
            '@html-eslint/element-newline': 'off',
            '@html-eslint/no-trailing-spaces': 'off',
            '@html-eslint/attrs-newline': 'off',
            '@html-eslint/use-baseline': 'off',
            '@html-eslint/no-extra-spacing-attrs': 'off',
        },
    },
    eslintConfigPrettier,
]);
