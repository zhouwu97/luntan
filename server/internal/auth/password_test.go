package auth

import "testing"

func TestBcryptPasswordHasherHashesAndVerifiesPassword(t *testing.T) {
	hasher := BcryptPasswordHasher{}
	hash, err := hasher.Hash("正确的密码123")
	if err != nil {
		t.Fatal(err)
	}
	if hash == "正确的密码123" {
		t.Fatal("password hash must not equal plaintext")
	}
	if err := hasher.Compare(hash, "正确的密码123"); err != nil {
		t.Fatalf("valid password was rejected: %v", err)
	}
	if err := hasher.Compare(hash, "错误的密码123"); err == nil {
		t.Fatal("invalid password was accepted")
	}
}
