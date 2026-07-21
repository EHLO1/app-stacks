curl -sSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py \
  | sudo python3 - \
  --core-address="ws://10.0.10.3:9120" \
  --connect-as="$HOSTNAME" \
  --onboarding-key=""