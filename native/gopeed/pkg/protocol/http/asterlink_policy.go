package http

// BaiduConnectionLimit bounds both new tasks and resumed range checkpoints.
// Zero means this provider does not use the Baidu connection policy.
func BaiduConnectionLimit(profile string) int {
	switch profile {
	case "baidu", "baidu_preview":
		return 1
	default:
		return 0
	}
}
