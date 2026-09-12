# Backend

Express + MongoDB API for authentication, admin user creation, and user-owned PDF document storage.

## Run

```bash
npm install
cp .env.example .env
npm run dev
```

## Seed Demo Users

```bash
npm run seed
```

Demo accounts:

- `admin@DBACD.com / Admin@123456`
- `user1 / 123456`
- `user2 / 123456`

## Admin Endpoints

- `GET /api/users`
- `POST /api/users`

Example payload:

```json
{
  "username": "employee1",
  "fullName": "Employee One",
  "password": "123456",
  "role": "user"
}
```
