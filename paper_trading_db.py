"""
Paper Trading Database Module
Handles storage and retrieval of paper trading data
"""

import sqlite3
import json
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import uuid

class PaperTradingDB:
    def __init__(self, db_path='paper_trading.db'):
        self.db_path = db_path
        self.init_database()
    
    def init_database(self):
        """Initialize the database with required tables"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Portfolio table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS portfolio (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                initial_value REAL DEFAULT 100000,
                current_value REAL DEFAULT 100000,
                total_pnl REAL DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Positions table (active trades)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS positions (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                symbol TEXT NOT NULL,
                trade_type TEXT NOT NULL,
                quantity INTEGER NOT NULL,
                entry_price REAL NOT NULL,
                current_price REAL NOT NULL,
                stop_loss REAL NOT NULL,
                target REAL NOT NULL,
                strategy TEXT,
                notes TEXT,
                risk_amount REAL NOT NULL,
                pnl REAL DEFAULT 0,
                status TEXT DEFAULT 'ACTIVE',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Trade history table (completed trades)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS trade_history (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                symbol TEXT NOT NULL,
                trade_type TEXT NOT NULL,
                quantity INTEGER NOT NULL,
                entry_price REAL NOT NULL,
                exit_price REAL NOT NULL,
                stop_loss REAL NOT NULL,
                target REAL NOT NULL,
                strategy TEXT,
                notes TEXT,
                risk_amount REAL NOT NULL,
                pnl REAL NOT NULL,
                exit_reason TEXT,
                entry_time TIMESTAMP,
                exit_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def get_or_create_portfolio(self, user_id: str) -> Dict:
        """Get or create portfolio for user"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Check if portfolio exists
        cursor.execute('SELECT * FROM portfolio WHERE user_id = ?', (user_id,))
        portfolio = cursor.fetchone()
        
        if not portfolio:
            # Create new portfolio
            cursor.execute('''
                INSERT INTO portfolio (user_id, initial_value, current_value, total_pnl)
                VALUES (?, 100000, 100000, 0)
            ''', (user_id,))
            conn.commit()
            
            # Fetch the created portfolio
            cursor.execute('SELECT * FROM portfolio WHERE user_id = ?', (user_id,))
            portfolio = cursor.fetchone()
        
        conn.close()
        
        return {
            'id': portfolio[0],
            'user_id': portfolio[1],
            'initial_value': portfolio[2],
            'current_value': portfolio[3],
            'total_pnl': portfolio[4],
            'created_at': portfolio[5],
            'updated_at': portfolio[6]
        }
    
    def get_active_positions(self, user_id: str) -> List[Dict]:
        """Get all active positions for user"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM positions 
            WHERE user_id = ? AND status = 'ACTIVE'
            ORDER BY created_at DESC
        ''', (user_id,))
        
        positions = cursor.fetchall()
        conn.close()
        
        return [self._position_to_dict(pos) for pos in positions]
    
    def get_trade_history(self, user_id: str, limit: int = 50) -> List[Dict]:
        """Get trade history for user"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM trade_history 
            WHERE user_id = ?
            ORDER BY exit_time DESC
            LIMIT ?
        ''', (user_id, limit))
        
        trades = cursor.fetchall()
        conn.close()
        
        return [self._trade_history_to_dict(trade) for trade in trades]
    
    def execute_trade(self, user_id: str, trade_data: Dict) -> Dict:
        """Execute a new paper trade"""
        try:
            trade_id = str(uuid.uuid4())
            
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Insert new position
            cursor.execute('''
                INSERT INTO positions (
                    id, user_id, symbol, trade_type, quantity, entry_price,
                    current_price, stop_loss, target, strategy, notes, risk_amount
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                trade_id,
                user_id,
                trade_data['symbol'],
                trade_data['type'],
                trade_data['quantity'],
                trade_data['entryPrice'],
                trade_data['entryPrice'],  # Initially same as entry
                trade_data['stopLoss'],
                trade_data['target'],
                trade_data.get('strategy', 'Manual'),
                trade_data.get('notes', ''),
                trade_data['riskAmount']
            ))
            
            conn.commit()
            conn.close()
            
            return {'success': True, 'trade_id': trade_id}
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def close_position(self, user_id: str, position_id: str, exit_price: float, exit_reason: str = 'MANUAL') -> Dict:
        """Close an active position"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Get position details
            cursor.execute('SELECT * FROM positions WHERE id = ? AND user_id = ?', (position_id, user_id))
            position = cursor.fetchone()
            
            if not position:
                return {'success': False, 'error': 'Position not found'}
            
            pos_dict = self._position_to_dict(position)
            
            # Calculate P&L
            if pos_dict['trade_type'].upper() == 'BUY':
                pnl = (exit_price - pos_dict['entry_price']) * pos_dict['quantity']
            else:  # SELL
                pnl = (pos_dict['entry_price'] - exit_price) * pos_dict['quantity']
            
            # Move to trade history
            cursor.execute('''
                INSERT INTO trade_history (
                    id, user_id, symbol, trade_type, quantity, entry_price,
                    exit_price, stop_loss, target, strategy, notes, risk_amount,
                    pnl, exit_reason, entry_time
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                position_id,
                user_id,
                pos_dict['symbol'],
                pos_dict['trade_type'],
                pos_dict['quantity'],
                pos_dict['entry_price'],
                exit_price,
                pos_dict['stop_loss'],
                pos_dict['target'],
                pos_dict['strategy'],
                pos_dict['notes'],
                pos_dict['risk_amount'],
                pnl,
                exit_reason,
                pos_dict['created_at']
            ))
            
            # Remove from active positions
            cursor.execute('DELETE FROM positions WHERE id = ? AND user_id = ?', (position_id, user_id))
            
            # Update portfolio
            self._update_portfolio_pnl(cursor, user_id, pnl)
            
            conn.commit()
            conn.close()
            
            return {'success': True, 'pnl': pnl}
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def update_position_prices(self, user_id: str, symbol: str, current_price: float):
        """Update current prices for positions"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE positions 
            SET current_price = ?, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = ? AND symbol = ? AND status = 'ACTIVE'
        ''', (current_price, user_id, symbol))
        
        conn.commit()
        conn.close()
    
    def update_position_price(self, position_id: str, current_price: float):
        """Update current price for a specific position"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE positions 
            SET current_price = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ? AND status = 'ACTIVE'
        ''', (current_price, position_id))
        
        conn.commit()
        conn.close()
    
    def get_symbol_trades(self, user_id: str, symbol: str, strategy: str = None) -> List[Dict]:
        """Get all trades for a specific symbol and strategy"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get active positions
        if strategy:
            cursor.execute('''
                SELECT * FROM positions 
                WHERE user_id = ? AND symbol = ? AND strategy = ?
            ''', (user_id, symbol, strategy))
        else:
            cursor.execute('''
                SELECT * FROM positions 
                WHERE user_id = ? AND symbol = ?
            ''', (user_id, symbol))
        
        active_positions = [self._position_to_dict(pos) for pos in cursor.fetchall()]
        
        # Get trade history
        if strategy:
            cursor.execute('''
                SELECT * FROM trade_history 
                WHERE user_id = ? AND symbol = ? AND strategy = ?
                ORDER BY exit_time DESC
            ''', (user_id, symbol, strategy))
        else:
            cursor.execute('''
                SELECT * FROM trade_history 
                WHERE user_id = ? AND symbol = ?
                ORDER BY exit_time DESC
            ''', (user_id, symbol))
        
        trade_history = [self._trade_history_to_dict(trade) for trade in cursor.fetchall()]
        
        conn.close()
        
        return active_positions + trade_history
    
    def _update_portfolio_pnl(self, cursor, user_id: str, pnl_change: float):
        """Update portfolio P&L"""
        cursor.execute('''
            UPDATE portfolio 
            SET total_pnl = total_pnl + ?,
                current_value = initial_value + total_pnl + ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE user_id = ?
        ''', (pnl_change, pnl_change, user_id))
    
    def _position_to_dict(self, position) -> Dict:
        """Convert position tuple to dictionary"""
        return {
            'id': position[0],
            'user_id': position[1],
            'symbol': position[2],
            'trade_type': position[3],
            'quantity': position[4],
            'entry_price': position[5],
            'current_price': position[6],
            'stop_loss': position[7],
            'target': position[8],
            'strategy': position[9],
            'notes': position[10],
            'risk_amount': position[11],
            'pnl': position[12],
            'status': position[13],
            'created_at': position[14],
            'updated_at': position[15]
        }
    
    def _trade_history_to_dict(self, trade) -> Dict:
        """Convert trade history tuple to dictionary"""
        return {
            'id': trade[0],
            'user_id': trade[1],
            'symbol': trade[2],
            'trade_type': trade[3],
            'quantity': trade[4],
            'entry_price': trade[5],
            'exit_price': trade[6],
            'stop_loss': trade[7],
            'target': trade[8],
            'strategy': trade[9],
            'notes': trade[10],
            'risk_amount': trade[11],
            'pnl': trade[12],
            'exit_reason': trade[13],
            'entry_time': trade[14],
            'exit_time': trade[15]
        }

# Global database instance
paper_trading_db = PaperTradingDB()