export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', ['feat', 'fix', 'refactor', 'release', 'test', 'chore', 'ci']],
    'header-max-length': [2, 'always', 100],
    'subject-forbidden-words': [2, 'always', ['WIP', 'REMOVE', 'fixup!', 'temp', 'MR feedback']],
  },
  plugins: [
    {
      rules: {
        'subject-forbidden-words': ({ subject }, _when, words) => {
          const hit = (words || []).find((w) =>
            new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i').test(subject || ''),
          );
          return [!hit, hit ? `subject may not contain "${hit}"` : ''];
        },
      },
    },
  ],
};
