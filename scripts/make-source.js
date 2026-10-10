// 產生 SideStore 來源清單（source.json），由 GitHub Actions 呼叫。
// SideStore 會定期讀這個檔案，發現 version 變大就提示更新。
const [owner, repo] = process.env.GITHUB_REPOSITORY.split('/');
const site = `https://${owner}.github.io/${repo}`;
const { VERSION, BUILD, SIZE } = process.env;

const source = {
  name: '記一筆',
  identifier: `io.github.${owner}.ledger.source`,
  sourceURL: `${site}/source.json`,
  apps: [
    {
      name: '記一筆',
      bundleIdentifier: `io.github.${owner}.ledger`,
      developerName: owner,
      localizedDescription: '自用的記帳 App：輸入金額、選類別就記好，看得到財產總額和每月收支。',
      iconURL: `${site}/icon.png`,
      tintColor: '#78BC96',
      versions: [
        {
          version: VERSION,
          buildVersion: BUILD,
          date: new Date().toISOString(),
          downloadURL: `https://github.com/${owner}/${repo}/releases/download/v${VERSION}/Ledger.ipa`,
          size: Number(SIZE),
          minOSVersion: '15.0'
        }
      ],
      appPermissions: { entitlements: [], privacy: {} }
    }
  ],
  news: []
};

process.stdout.write(JSON.stringify(source, null, 2) + '\n');
