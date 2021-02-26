#!/bin/bash -eu

# ロールのトークンを取得するスクリプト
# AssumeRoleのMFA認証済みトークンが取得できるため
# トークンの期限中はAWSコマンド実行時にMFA認証しなくて良くなる
# セッション情報はAWS Profileに設定される
#
# 前提
# AssumeRole先のProfileに source_profile と role_arn が設定されていること
# また、MFA認証が必要な場合は mfa_serial も設定されていること
#
# 使い方
# ./update-assume-role-token.sh <トークンを取得したいプロフィール名>

## 認証情報の取得に必要な情報を取得
if [ $# != 1 ]; then
    echo '引数にプロファイル名を入力してください'
    exit 1
fi
profile=$1
source_profile=$(aws configure get source_profile --profile $profile)
role_arn=$(aws configure get role_arn --profile $profile)

## mfa認証が必要な設定になっているかチェック
## NOTE: aws configure getは値が設定されていなかった場合code1で終了するため、eオプションを一時的に外す
set +e
mfa_serial=$(aws configure get mfa_serial --profile $profile)
set -e

## mfa認証オプションを設定
mfa_serial_option=""
token_code_option=""
if [ -n "$mfa_serial" ]; then
  echo -n "Assume Role MFA token code: "
  read token_code
  token_code_option="--token-code $token_code"
  mfa_serial_option="--serial-number $mfa_serial"
fi

## 一時認証情報を取得する
credentials=$(aws sts assume-role \
  --profile $source_profile \
  $token_code_option \
  $mfa_serial_option \
  --role-arn $role_arn \
  --role-session-name $profile \
  --query "Credentials.[AccessKeyId, SecretAccessKey, SessionToken, Expiration]" \
  --output text)

## 一時的認証情報をaws cli のプロファイルにセットする
access_key_id=$(echo $credentials | cut -d ' ' -f 1)
secret_access_key=$(echo $credentials | cut -d ' ' -f 2)
session_token=$(echo $credentials | cut -d ' ' -f 3)
expire=$(echo $credentials | cut -d ' ' -f 4)
aws configure set aws_access_key_id "$access_key_id" --profile=$profile
aws configure set aws_secret_access_key "$secret_access_key" --profile=$profile
aws configure set aws_session_token "$session_token" --profile=$profile
aws configure set expire "$expire" --profile=$profile

## プロファイル情報を表示
aws configure list --profile $profile
## expireを他のプロファイル情報に合わせたフォーマットにして表示
unix_time=$(date -u -jf %FT%T+00:00 $expire +%s)
jst=$(date -r $unix_time +%FT%T)
printf "%10s %24s %16s\n" 'expire' $jst 'info'
