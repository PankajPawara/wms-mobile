class ValidationData {
  // A set of valid model codes to look for in part numbers
  // This is used for auto-correcting common OCR mistakes (e.g. KOV -> K0V)
  static const Set<String> validModelCodes = {
    'KPL', 'KWP-9', 'KWP-D', 'KWP-F', 'KWP-G', 'KWP-H00', 'KWP-H20', 
    'K0P', 'K24', 'K0L', 'K32', 'KVT', 'KRP', 'KZK-D', 'KZK-D20', 
    'K0Y', 'KRB', 'K74', 'K86', 'K1J', 'K0E', 'KPP', 'KYJ', 'KTE-9', 
    'KTE-60', 'KTE-65', 'KTE-D', 'K0V', 'K67', 'K0N', 'K3C', 'KSP', 
    'K38', 'K1K', 'KSP-B', 'K14', 'KYY', 'K63', 'K1E', 'K55', 'K1C', 
    'K43', 'K1L', 'KWF', 'KWS', 'K23', 'K21'
  };

  // Main Area -> Sub Areas mapping
  // Used to extract specific sub-areas from customer names
  static const Map<String, List<String>> areaSchedules = {
    // Out City
    'ANAVAL': ['MAHUVA'],
    'VANSADA': ['RANKUVA', 'CHIKHLI', 'DUNGARI'],
    'WAGAHI': ['UNAI', 'AAHAVA'],
    'VALSAD': ['DODHIKUVA'],
    'KARCHELIYA': [],
    'VAPI': ['DAMAN', 'BHILAD', 'ATUL', 'UDWADA', 'KILLAPARDI', 'NANAPAUDHA', 'DHARAMPUR', 'KHERGAM', 'GOLWAD', 'SELVASSA', 'CHALA', 'DADHRA'],
    'KIM': ['KOSAMBA', 'SAYAN'],
    'KAMREJ': ['KADODARA', 'CHALTHAN', 'VALTHAN', 'VELENJA'],
    'SONGADH': ['BARDOLI', 'VYARA', 'BAJIPURA', 'BUHARI', 'MADHI', 'VALOD', 'NAVAPUR'],
    'NAVSARI': ['SACHIN', 'BHESTAN', 'UNN', 'BILIMORA', 'GANDEVI', 'PALSANA'],
    'ANKLESHWER': ['BHARUCH', 'VALIYA', 'MOSALI', 'VANKAL', 'TADKESHWAR', 'ZADESHWAR'],
    'RAJPARDI': ['UMALLA', 'RAJPIPLA', 'JHAGADIA', 'DEDIYAPADA', 'SELMBA', 'SAGBARA', 'NETRANG', 'CHASVAD', 'ZANKHVAV', 'MANDAVI'],
    'BARDOLI': ['SONGADH', 'VYARA'],
    
    // City
    'KATARGAM': ['LAL DARWAJA', 'AMROLI', 'SIGANPUR', 'VED ROAD', 'GAJERA CIRCLE', 'SAYAN ROAD', 'L D ROAD', 'DELHI GATE', 'PUMPING', 'SAIYADPURA'],
    'SALABATPURA': ['NAVSARIBAZAR', 'NANPURA', 'RING ROAD', 'BEGUMPURA', 'MUGLISARA', 'WADIFALIYA', 'RUSTAMPURA', 'GOPIPURA', 'BHAGAL', 'BHAVANIWAD', 'VAKHARIA', 'DHAYANA'],
    'RANDER': ['BHATAR', 'L P SAVANI ROAD', 'PAL', 'ADAJAN', 'VESU', 'CITYLIGHT', 'PIPLOD', 'JAHANGIRPURA', 'OLPAD', 'RAMNAGAR', 'PALANPUR PATIYA', 'ALTHAN', 'VIP ROAD', 'MORABHAGAL', 'PARLE POINT', 'ICCHAPORE'],
    'UDHANA': ['DINDOLI', 'BAMROLI ROAD', 'PANDESARA', 'BHATHENA', 'NAVAGAM', 'U M ROAD', 'AMBANAGAR', 'HARINAGAR'],
    'PARVAT PATIYA': ['MAGOB', 'NANA VARACHHA', 'SIMADA', 'YOGI CHOWK', 'SITANAGAR', 'PUNAGAM', 'LASKANA', 'KARGIL CHOWK', 'MOTA VARACHHA', 'GODADRA', 'SARTHANA', 'SPINING MILL', 'CHOPATI', 'PASODARA', 'RESMA'],
    'VARACHHA': ['L.H.ROAD', 'GODADRA', 'MATAWADI', 'MODERN TOWN', 'KAPODARA', 'INTERCITY', 'SPINING MILL', 'HIRABAG', 'A.K ROAD', 'CANAL ROAD'],
  };
}
