package auth

import "golang.org/x/crypto/bcrypt"

// BcryptPasswordHasher 使用成熟的慢哈希算法保存密码凭据。
type BcryptPasswordHasher struct{}

func (BcryptPasswordHasher) Hash(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func (BcryptPasswordHasher) Compare(hash string, password string) error {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
}
