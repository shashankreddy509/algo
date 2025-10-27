# Fyers Trading Flask App

A modern web application built with Flask that integrates with the Fyers API for trading and portfolio management.

## Features

- **Secure Authentication**: OAuth 2.0 integration with Fyers API
- **Real-time Data**: Access to profile information and funds data
- **Modern UI**: Responsive design with Bootstrap 5
- **API Endpoints**: RESTful API for profile and funds data
- **Session Management**: Secure session handling

## Prerequisites

- Python 3.7 or higher
- Fyers API credentials (Client ID and Secret Key)
- Active Fyers trading account

## Installation

1. **Clone or download the project**
   ```bash
   cd py-trade
   ```

2. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure environment variables**
   
   Edit the `.env` file and add your Fyers API credentials:
   ```
   FYERS_CLIENT_ID=your_actual_client_id
   FYERS_SECRET_KEY=your_actual_secret_key
   FYERS_REDIRECT_URI=http://localhost:5000/callback
   FLASK_SECRET_KEY=your_secure_random_secret_key
   ```

   **Important**: Replace the placeholder values with your actual Fyers API credentials.

## Getting Fyers API Credentials

1. Visit the [Fyers API Portal](https://api-dashboard.fyers.in/)
2. Create a new app or use an existing one
3. Note down your Client ID and Secret Key
4. Set the redirect URI to `http://localhost:5000/callback`

## Running the Application

1. **Start the Flask development server**
   ```bash
   python app.py
   ```

2. **Access the application**
   
   Open your browser and navigate to: `http://localhost:5000`

## Usage

1. **Login**: Click "Login with Fyers" to authenticate with your Fyers account
2. **Dashboard**: View your profile information and funds data
3. **API Access**: Use the API endpoints for programmatic access

## API Endpoints

- `GET /api/profile` - Get user profile information
- `GET /api/funds` - Get funds and margin information

## Project Structure

```
py-trade/
├── app.py              # Main Flask application
├── requirements.txt    # Python dependencies
├── .env               # Environment variables (configure this!)
├── README.md          # This file
└── templates/         # HTML templates
    ├── base.html      # Base template
    ├── index.html     # Home page
    └── dashboard.html # Dashboard page
```

## Security Notes

- Never commit your `.env` file to version control
- Use strong, unique secret keys
- The redirect URI must match exactly with your Fyers app configuration
- Sessions are secured with Flask's session management

## Troubleshooting

### Common Issues

1. **"Invalid client_id" error**
   - Verify your Client ID in the `.env` file
   - Ensure there are no extra spaces or characters

2. **"Redirect URI mismatch" error**
   - Check that the redirect URI in your Fyers app matches `http://localhost:5000/callback`
   - Ensure the URI in `.env` file matches exactly

3. **"Access token generation failed"**
   - Verify your Secret Key is correct
   - Check that your Fyers account has API access enabled

### Debug Mode

The application runs in debug mode by default. For production deployment:

1. Set `debug=False` in `app.py`
2. Use a production WSGI server like Gunicorn
3. Set up proper environment variable management

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is for educational and personal use. Please comply with Fyers API terms of service.

## Support

For issues related to:
- **Fyers API**: Contact Fyers support
- **This application**: Create an issue in the repository

---

**Disclaimer**: This application is for educational purposes. Always test thoroughly before using with real trading accounts.