#!/bin/bash
cd "$(dirname "$0")"
cd ../oxidized/output/configs.git
git push --force
git diff HEAD^ ${OX_REPO_COMMITREF} > /tmp/config_diff_oxidized.txt
curl  -F file=@/tmp/config_diff_oxidized.txt -F "initial_comment=${OX_NODE_NAME} got a config update. View the commit here: https://github.com/gathering/netconfig/commit/${OX_REPO_COMMITREF}" -F filename=${OX_REPO_COMMITREF} -F filetype=diff -F channels=C<CHANNEL ID> -H "Authorization: Bearer xoxb-<TOKEN>" https://slack.com/api/files.upload
rm /tmp/config_diff_oxidized.txt
