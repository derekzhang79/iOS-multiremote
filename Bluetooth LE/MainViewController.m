//
//  ViewController.m
//  Bluetooth LE
//
//  Created by Jens Willy Johannsen on 30-04-12.
//  Copyright (c) 2012 Greener Pastures. All rights reserved.
//

#import "MainViewController.h"
#import "CBUUID+Utils.h"
#import "MBProgressHUD.h"
#import "TBXML.h"
#import "PageListViewController.h"
#import "ButtonModel.h"

#define UUID_GCAC_SERVICE @"b8b96269-562a-408f-8155-0b45f21c7774"
#define UUID_DEVICE_INFORMATION @"180a"
#define UUID_COMMAND_CHARATERISTIC @"bf33aeaf-8653-4841-89c8-330fa4f13346"
#define UUID_RESPONSE_CHARACTERISTIC @"51494780-28c9-4502-87f1-c23881c70300"

#define COMMAND_NUMBER @"commandNumber"

// Coordinates for buttons
static const CGFloat xCoords[] = {24, 117, 210};
static const CGFloat yCoords[] = {7, 101, 195, 289};

@interface MainViewController ()
- (void)print:(NSString*)text;
- (void)scanTimeout:(NSTimer*)timer;
- (void)populateTitleLabelScroller:(NSArray*)pageTitles;
- (void)parseXMLFile:(NSString*)xmlFileName;
- (void)sendCommand:(NSUInteger)commandNumber;
- (void)iPhone_readPages:(TBXMLElement*)rootElement;
- (void)iPad_readPages:(TBXMLElement*)rootElement;
- (void)disableButtons;
- (void)enableButtons;

@end

@implementation MainViewController
@synthesize centralManager, peripherals, connectedPeripheral, GCACService, GCACCommandCharacteristic, GCACResponseCharacteristic, peripheralNames, pages, pageContent, masterViewController, currentButtonsView = _currentButtonsView, currentPageName;
@synthesize learnButton;
@synthesize debugButton;
@synthesize scanButton;
@synthesize flexSpace;
@synthesize toolbar;
@synthesize pageLabelScroller;
@synthesize textView;
@synthesize debugView;
@synthesize mainScroller;

- (void)viewDidLoad
{
    [super viewDidLoad];

	// Set background for iPad
	// iPhone or iPad?
	if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
		self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"metal_pattern.png"]];

	// Power up Bluetooth LE central manager (main queue)
	centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
	// Wait for callback to report BTLE ready.
	
	// Initialize
	peripherals = [[NSMutableArray alloc] init];
	peripheralNames = [[NSMutableDictionary alloc] init];	
	
	// Load sound
	NSError *error = nil;
	audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"tock" ofType:@"aif"]] error:&error];
	NSAssert( error == nil, @"Error loading sound: %@", [error localizedDescription] );
    [audioPlayer prepareToPlay];
	
	// Appearance
	[debugButton setBackgroundImage:[UIImage imageNamed:@"topbtn_debug.png"] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	[scanButton setBackgroundImage:[UIImage imageNamed:@"topbtn_scan.png"] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	[learnButton setBackgroundImage:[UIImage imageNamed:@"topbtn_learn.png"] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	
	// Set toolbar items
	toolbarItems = [NSMutableArray arrayWithObjects:flexSpace, scanButton, debugButton, nil];
	[toolbar setItems:toolbarItems animated:YES];
	 
	// Load xml
	[self parseXMLFile:@"remote.xml"];
	
	// Disable all buttons requiring a connection
	[self disableButtons];
	
	commandMode = CommandModeIdle;
}

- (void)viewDidUnload
{
	[self setTextView:nil];
    [self setDebugView:nil];
	[self setLearnButton:nil];
	[self setDebugButton:nil];
	[self setScanButton:nil];
	[self setMainScroller:nil];
	[self setFlexSpace:nil];
	[self setToolbar:nil];
	[self setPageLabelScroller:nil];
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	// iPhone or iPad?
	if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
	{
		// All orientations supported for iPad
		return YES;
	}
	else
	{
		// iPhone supports only portrait orientations
		return UIInterfaceOrientationIsPortrait( interfaceOrientation );
	}
}

#pragma mark - UIScrollViewDelegate methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
	// Calculate position for title scroller: one page in the main scroller corresponds to 80px in the title scroller
	CGFloat titleScrollerOffset = -160 + mainScroller.contentOffset.x / 320 * 80;
	pageLabelScroller.contentOffset = CGPointMake( titleScrollerOffset, 0 );
}

#pragma mark - Private methods

- (void)populateTitleLabelScroller:(NSArray*)pageTitles{
	CGFloat xPos = 0;
	CGFloat maxX = 0;
	
	for( NSString *pageTitle in pageTitles )
	{
		// Create label
		UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
		label.backgroundColor = [UIColor clearColor];
		label.font = [UIFont boldSystemFontOfSize:[UIFont systemFontSize]];
		label.textColor = [UIColor whiteColor];
		label.shadowColor = [UIColor blackColor];
		label.shadowOffset = CGSizeMake( 0, 1 );
		label.text = pageTitle;
		[label sizeToFit];
		
		// Position
		CGRect frame = label.frame;
		frame.origin.x = xPos - frame.size.width/2;
		frame.origin.y = pageLabelScroller.bounds.size.height/2 - frame.size.height/2;
		label.frame = frame;
		xPos += 80;
		maxX = CGRectGetMaxX( label.frame );
		
		[pageLabelScroller addSubview:label];
	}
	
	// Initial position
	pageLabelScroller.contentSize = CGSizeMake( maxX, pageLabelScroller.bounds.size.height );
	pageLabelScroller.contentOffset = CGPointMake( -160, 0 );
}

- (void)print:(NSString *)text
{
	DEBUG_LOG( @"--> %@", text );
#if DEBUG
	textView.text = [textView.text stringByAppendingFormat:@"\r%@", text];
	[textView scrollRangeToVisible:NSMakeRange( [textView.text length]-1, 1 )];
#endif
}

- (void)scanTimeout:(NSTimer *)timer
{
	// Stop scanning
	[centralManager stopScan];
	[MBProgressHUD hideHUDForView:self.view animated:YES];
	[self print:@"Done scanning."];
	
	// We're done scanning for devices. If we're not yet connecting, let the user pick a device if we found any
	if( [peripherals count] > 0 )
	{
		// We found some: show action sheet
		UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"Connect to device" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:nil];
		
		// Iterate devices
		for( CBPeripheral *peripheral in peripherals )
		{
			// Do we have a name for the device?
			if( [peripheralNames objectForKey:[CBUUID stringFromCFUUIDRef:peripheral.UUID]] )
				// Yes: use the name
				[actionSheet addButtonWithTitle:[peripheralNames objectForKey:[CBUUID stringFromCFUUIDRef:peripheral.UUID]]];
			else 
				// No: use UUID
				[actionSheet addButtonWithTitle:[CBUUID stringFromCFUUIDRef:peripheral.UUID]];
		}
		[actionSheet showInView:self.view];
	}
	else 
	{
		[self print:@"... no devices found."];
		
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No devices found" message:@"Make sure the device is switched on and in range." delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
		[alert show];
		
		// Set last item of the toolbar to the scan button (enabled)
		scanButton.enabled = YES;
		if( [toolbarItems containsObject:learnButton] )
		{
			[toolbarItems insertObject:scanButton atIndex:[toolbarItems indexOfObject:learnButton]];
			[toolbarItems removeObject:learnButton];
		}
		[toolbar setItems:toolbarItems animated:YES];
	}
}

- (void)sendCommand:(NSUInteger)commandNumber
{
	if( self.connectedPeripheral == nil )
	{
		[self print:@"Not connected."];
		return;
	}
	
	// Build command string
	NSString *commandPrefix = (learning ? @"L" : @"S");
	NSString *commandString = [NSString stringWithFormat:@"%@-%03d", commandPrefix, commandNumber];
	[self print:[NSString stringWithFormat:@"Sending \"%@", commandString]];
	[connectedPeripheral writeValue:[commandString dataUsingEncoding:NSUTF8StringEncoding] forCharacteristic:GCACCommandCharacteristic type:CBCharacteristicWriteWithResponse];
	
	// Not learning anymore
	if( learning )
	{
		learning = NO;
		
		// Change font color on all buttons
		[mainScroller.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			if( [obj isKindOfClass:[UIButton class]] )
			{
				UIButton *button = (UIButton*)obj;	// Typecast
				[button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
				[button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
			}
		}];
	}
}

#pragma mark - UIActionSheetDelegate methods

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	// Was it cancel?
	if( buttonIndex == actionSheet.cancelButtonIndex )
		// Yes: do nothing
		return;
	
	// Otherwise, connect to specified device
	[MBProgressHUD showHUDAddedTo:self.view animated:YES];
	CBPeripheral *peripheral = [peripherals objectAtIndex:buttonIndex - 1];	// -1 for the Cancel button
	[centralManager connectPeripheral:peripheral options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
}

#pragma mark - CBCentralManagerDelegate methods

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
	switch( central.state )
	{
        case CBCentralManagerStateUnknown: 
        case CBCentralManagerStateResetting:
			break;

        case CBCentralManagerStateUnsupported:
			[self print:@"Core Bluetooth not supported on this device."];
			break;

        case CBCentralManagerStateUnauthorized:
			[self print:@"Core Bluetooth not authorized."];
			break;
			
        case CBCentralManagerStatePoweredOff:
			[self print:@"Core Bluetooth powered off."];
			break;
			
        case CBCentralManagerStatePoweredOn:
			[self print:@"Core Bluetooth ready."];
			break;
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
	// Perepheral discovered: add it
	[peripherals addObject:peripheral];
	
	[self print:[NSString stringWithFormat:@"Found peripheral with UUID %@, advertisement %@", [CBUUID stringFromCFUUIDRef:peripheral.UUID], [advertisementData description]]];
	
	// Is it the preferred device?
	CBUUID *uuid = [CBUUID UUIDWithCFUUID:peripheral.UUID];
	if( [uuid isEqualToUUID:APP.preferredDeviceUUID] )
	{
		// Yes: stop scanning and connect immediately
		[self print:@"Found preferred device – connecting..." ];
		[centralManager stopScan];
		[scanTimer invalidate];	// So we don't get to the "done scanning" method
		
		// Connect...
		[centralManager connectPeripheral:peripheral options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
	}
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
	// Hide HUD
	[MBProgressHUD hideHUDForView:self.view animated:YES];
	
	[self print:[NSString stringWithFormat:@"Connected to peripheral: %@", [CBUUID stringFromCFUUIDRef:peripheral.UUID]]];
	
	// Set property and remember as preferred device
	peripheral.delegate = self;
	self.connectedPeripheral = peripheral; 
	APP.preferredDeviceUUID = [CBUUID UUIDWithCFUUID:peripheral.UUID];
	
	// Find the GCAC service
	[peripheral discoverServices:[NSArray arrayWithObject:[CBUUID UUIDWithString:UUID_GCAC_SERVICE]]];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
	// Check for error
	if( error != nil )
	{
		// Error
		[self print:[NSString stringWithFormat:@"Error disconnecting peripheral: %@", [error localizedDescription]]];
		return;
	}

	[self print:@"Peripheral disconnected"];
	self.connectedPeripheral = nil;
	
	// Disable all buttons requiring a connection
	[self disableButtons];
	[toolbar setItems:[NSArray arrayWithObjects:debugButton, flexSpace, scanButton, nil] animated:YES];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
	[self print:[NSString stringWithFormat:@"Could not connect to peripheral. Error: %@", [error localizedDescription] ]];
}

#pragma mark - CBPeripheralDelegate methods

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
	// Check for error
	if( error != nil )
	{
		// Error
		[self print:[NSString stringWithFormat:@"Error discovering services: %@", [error localizedDescription]]];
		return;
	}
	
	[self print:@"Done discovering services."];
	
	// Find the GCAC service (altough it's the only one we're trying to discover)
	for( CBService *service in peripheral.services )
	{
		if( [service.UUID isEqualToUUIDString:UUID_GCAC_SERVICE] )
		{
			self.GCACService = service;
			[self print:@"Found GCAC service"];
			
			// Find characteristics from GCAC service
			[connectedPeripheral discoverCharacteristics:[NSArray arrayWithObjects:[CBUUID UUIDWithString:UUID_COMMAND_CHARATERISTIC], [CBUUID UUIDWithString:UUID_RESPONSE_CHARACTERISTIC], nil] forService:service];
		}
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
	// Check for error
	if( error != nil )
	{
		// Error
		[self print:[NSString stringWithFormat:@"Error discovering characteristics: %@", [error localizedDescription]]];
		return;
	}
	
	// Which service did we find characteristics for?
	if( service == GCACService )
	{
		// The GCAC service: get pointers to command and response characteristics
		for( CBCharacteristic *characteristic in service.characteristics )
		{
			if( [characteristic.UUID isEqualToUUIDString:UUID_COMMAND_CHARATERISTIC] )
			{
				[self print:@"Found command characteristic"];
				self.GCACCommandCharacteristic = characteristic;
				
				// We have the command characteristic: enable buttons
				[self enableButtons];
				
				// Set toolbar items
				[toolbar setItems:[NSArray arrayWithObjects:debugButton, flexSpace, learnButton, nil] animated:YES];
			}
			else if( [characteristic.UUID isEqualToUUIDString:UUID_RESPONSE_CHARACTERISTIC] )
			{
				[self print:@"Found response characteristic"];
				self.GCACResponseCharacteristic = characteristic;
				
				// Enable notifications for response characteristic
				[peripheral setNotifyValue:YES forCharacteristic:characteristic];
			}
		}
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
	// Check for error
	if( error != nil )
	{
		// Error
		[self print:@"Error enabling notifications for response characteristic"];
		return;
	}
	
	[self print:@"Response notifications enabled"];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
	// Check for error
	if( error != nil )
	{
		// Error
		[self print:[NSString stringWithFormat:@"Error updating value for characteristic %@: %@", [characteristic.UUID string], [error localizedDescription]]];
		return;
	}
	
	// Get user friendly name for characteristic if possible
	NSString *characteristicName;
	if( characteristic == GCACCommandCharacteristic )
		characteristicName = @"COMMAND";
	else if( characteristic == GCACResponseCharacteristic )
		characteristicName = @"RESPONSE";
	else 
		characteristicName = [characteristic.UUID string];
	
	NSString *valueString = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
	[self print:[NSString stringWithFormat:@"Value updated for %@ = '%@'", characteristicName, valueString]];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
	// Check for error
	if( error != nil )
	{
		// Error
		[self print:[NSString stringWithFormat:@"Error writing command value: %@", [characteristic.UUID string], [error localizedDescription]]];
		return;
	}
	
	// Should we continue to send the command?
	if( commandMode == CommandModeRepeat )
		// Yes
		[self sendCommand:currentCommandNumber];
}

#pragma mark - UISplitViewController delegate methods

- (void)splitViewController:(UISplitViewController *)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)pc
{
	[barButtonItem setBackgroundImage:[UIImage imageNamed:@"topbtn_debug.png"] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];

	// Add the button to toolbar items array
	[toolbarItems insertObject:barButtonItem atIndex:0];
	[toolbar setItems:toolbarItems animated:YES];
}

- (void)splitViewController:(UISplitViewController *)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
	// Remove the bar button from toolbar items
	[toolbarItems removeObject:barButtonItem];
	[toolbar setItems:toolbarItems animated:YES];
}

#pragma mark - ButtonModelDelegate methods

- (void)repeatCommand:(UIButton*)sender
{
	currentCommandNumber = sender.tag;
	commandMode = CommandModeRepeat;
	
	// Play sound
	[audioPlayer play];
	
	// Send command
	[self sendCommand:currentCommandNumber];
}

/* Stops the repeatable command from transmitting.
 */
- (void)cancelRepeatCommand:(id)sender
{
	// Stop repeating
	commandMode = CommandModeIdle;
}

- (void)sendCommandAction:(UIButton*)sender
{
	// Play sound
	[audioPlayer play];
	
	[self sendCommand:sender.tag];
}

#pragma mark - XML parser methods

- (void)parseXMLFile:(NSString*)xmlFileName
{
	
	/// TEMP: get from iTunes documents instead
	NSError *error = nil;
	TBXML *xml = [TBXML newTBXMLWithXMLFile:xmlFileName error:&error];
	NSAssert( error == nil, @"Error opening xml file: %@", [error localizedDescription] );
	
	// Iterate pages
	// iPhone or iPad?
	if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
		// iPad: parse and create 
		[self iPad_readPages:xml.rootXMLElement];
	else
		// iPhone: parse and add to mainScroller and titleScroller
		[self iPhone_readPages:xml.rootXMLElement];
}

- (void)iPad_readPages:(TBXMLElement*)rootElement
{
	// Get layout info
	NSString *layoutPlistFilePath = [[NSBundle mainBundle] pathForResource:@"coordinates-iPad" ofType:@"plist"];
	NSDictionary *layoutInfo = [NSDictionary dictionaryWithContentsOfFile:layoutPlistFilePath];
	NSAssert( layoutInfo != nil, @"Error opening layout coordinates file!" );
	
	// Temporary array and dictionary for holding page names and buttons
	NSMutableArray *tmpArray = [[NSMutableArray alloc] init];
	NSMutableDictionary *tmpDictionary = [[NSMutableDictionary alloc] init];
	
	// Iterate pages
	TBXMLElement *page = [TBXML childElementNamed:@"page" parentElement:rootElement];
	while( page )
	{
		int x=0, y=0;	// Coordinates
		
		// Add page name to array
		NSString *pageName = [TBXML valueOfAttributeNamed:@"name" forElement:page];
		[tmpArray addObject:pageName];
		DEBUG_LOG( @"Found page '%@'", pageName );
		
		// Which layout?
		NSString *layout = [TBXML valueOfAttributeNamed:@"layout" forElement:page];
		NSDictionary *pageLayoutInfo = [layoutInfo objectForKey:layout];
		NSAssert1( pageLayoutInfo, @"Unknown page layout: %@", layout );
		
		// Get coords from plist dictionary
		int columns = [[pageLayoutInfo objectForKey:@"columns"] intValue];
		int rows = [[pageLayoutInfo objectForKey:@"rows"] intValue];
		NSString *filenameFormat = [pageLayoutInfo objectForKey:@"filenameFormat"];
		CGFloat initialX = [[pageLayoutInfo objectForKey:@"initialX"] floatValue];
		CGFloat initialY = [[pageLayoutInfo objectForKey:@"initialY"] floatValue];
		CGFloat stepX = [[pageLayoutInfo objectForKey:@"stepX"] floatValue];
		CGFloat stepY = [[pageLayoutInfo objectForKey:@"stepY"] floatValue];
		
		// Create view for this page
		UIView *pageView = [[UIView alloc] initWithFrame:CGRectMake( 0, CGRectGetMaxY( toolbar.frame ), self.view.bounds.size.width, self.view.bounds.size.height - CGRectGetMaxY( toolbar.frame ))];
		pageView.backgroundColor = [UIColor clearColor];
		
		// Iterate rows
		CGFloat xPos;
		CGFloat yPos = initialY;	// Initial y position
		TBXMLElement *rowElement = [TBXML childElementNamed:@"row" parentElement:page];
		while( rowElement )
		{
			// Reset x position
			xPos = initialX;
			
			// Iterate buttons
			TBXMLElement *buttonElement = [TBXML childElementNamed:@"button" parentElement:rowElement];
			while( buttonElement )
			{
				// Instantiate button from XML
				ButtonModel *buttonModel = [ButtonModel buttonModelFromXMLNode:buttonElement];
				
				// Create and configure button
				UIButton *btn = [buttonModel buttonForDelegate:self filenameFormat:filenameFormat];
				if( btn )
				{
					CGRect frame = btn.frame;
					frame.origin = CGPointMake( xPos, yPos );
					btn.frame = frame;
					
					// Add to view
					[pageView addSubview:btn];
				}
				
				// Next button
				xPos += stepX;
				NSAssert( x < columns, @"Too many buttons in row: %s", rowElement->text );
				x++;
				buttonElement = [TBXML nextSiblingNamed:@"button" searchFromElement:buttonElement];
			}
			
			// Next row
			yPos += stepY;
			x = 0;
			NSAssert( y < rows, @"Too many rows in page: %s", page->text );
			y++;
			rowElement = [TBXML nextSiblingNamed:@"row" searchFromElement:rowElement];
		}
		
		// Store view in dictionary with page name as key
		[tmpDictionary setObject:pageView forKey:pageName];
		
		// Next page
		page = [TBXML nextSiblingNamed:@"page" searchFromElement:page];
	}
	
	// Set array and dictionary
	pages = [[NSArray alloc] initWithArray:tmpArray];
	pageContent = [[NSDictionary alloc] initWithDictionary:tmpDictionary];
	
	/// TEMP: select first page
	self.currentButtonsView = [pageContent objectForKey:[pages objectAtIndex:0]];
	currentPageName = [pages objectAtIndex:0];

	// Reload pages list
	[masterViewController.tableView reloadData];
}

- (void)iPhone_readPages:(TBXMLElement*)rootElement
{
	// Get iPhone layout info
	NSString *layoutPlistFilePath = [[NSBundle mainBundle] pathForResource:@"coordinates" ofType:@"plist"];
	NSDictionary *layoutInfo = [NSDictionary dictionaryWithContentsOfFile:layoutPlistFilePath];
	NSAssert( layoutInfo != nil, @"Error opening layout coordinates file!" );
	
	TBXMLElement *page = [TBXML childElementNamed:@"page" parentElement:rootElement];
	NSMutableArray *pageNames = [NSMutableArray array];
	CGFloat pageOffset = 0;
	while( page )
	{
		int x=0, y=0;	// Coordinates
		NSString *pageName = [TBXML valueOfAttributeNamed:@"name" forElement:page];
		[pageNames addObject:pageName];
		DEBUG_LOG( @"Found page '%@'", pageName );
		
		// Which layout?
		NSString *layout = [TBXML valueOfAttributeNamed:@"layout" forElement:page];
		NSDictionary *pageLayoutInfo = [layoutInfo objectForKey:layout];
		NSAssert1( pageLayoutInfo, @"Unknown page layout: %@", layout );
		
		// Get coords from plist dictionary
		int columns = [[pageLayoutInfo objectForKey:@"columns"] intValue];
		int rows = [[pageLayoutInfo objectForKey:@"rows"] intValue];
		NSString *filenameFormat = [pageLayoutInfo objectForKey:@"filenameFormat"];
		CGFloat initialX = [[pageLayoutInfo objectForKey:@"initialX"] floatValue];
		CGFloat initialY = [[pageLayoutInfo objectForKey:@"initialY"] floatValue];
		CGFloat stepX = [[pageLayoutInfo objectForKey:@"stepX"] floatValue];
		CGFloat stepY = [[pageLayoutInfo objectForKey:@"stepY"] floatValue];
		
		// Iterate rows
		CGFloat xPos;
		CGFloat yPos = initialY;	// Initial y position
		TBXMLElement *rowElement = [TBXML childElementNamed:@"row" parentElement:page];
		while( rowElement )
		{
			// Reset x position
			xPos = initialX;
			
			// Iterate buttons
			TBXMLElement *buttonElement = [TBXML childElementNamed:@"button" parentElement:rowElement];
			while( buttonElement )
			{
				// Instantiate button from XML
				ButtonModel *buttonModel = [ButtonModel buttonModelFromXMLNode:buttonElement];
				
				// Create and configure button
				UIButton *btn = [buttonModel buttonForDelegate:self filenameFormat:filenameFormat];
				CGRect frame = btn.frame;
				frame.origin = CGPointMake( xPos + pageOffset, yPos );
				btn.frame = frame;
				
				// Add it
				[mainScroller addSubview:btn];
				
				// Next button
				xPos += stepX;
				NSAssert( x < columns, @"Too many buttons in row: %s", rowElement->text );
				x++;
				buttonElement = [TBXML nextSiblingNamed:@"button" searchFromElement:buttonElement];
			}
			
			// Next row
			yPos += stepY;
			x = 0;
			NSAssert( y < rows, @"Too many rows in page: %s", page->text );
			y++;
			rowElement = [TBXML nextSiblingNamed:@"row" searchFromElement:rowElement];
		}
		
		// Next page
		pageOffset += mainScroller.bounds.size.width;
		page = [TBXML nextSiblingNamed:@"page" searchFromElement:page];
	}
	
	// Set content size
	mainScroller.contentSize = CGSizeMake( pageOffset, mainScroller.bounds.size.height );
	
	// Set page titles
	[self populateTitleLabelScroller:pageNames];
}

#pragma mark - Other methods

- (void)disableButtons
{
	// iPhone or iPad?
	if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
	{
		// iPad: disable buttons in all views
		for( UIView *view in [pageContent allValues] )
		{
			for( UIView *subview in view.subviews )
				if( [subview isKindOfClass:[UIButton class]] )
					[(UIButton*)subview setEnabled:NO];
		}
	}
	else
	{
		// iPhone: enumerate subviews in mainscroller
		for( UIView *subview in mainScroller.subviews )
			if( [subview isKindOfClass:[UIButton class]] )
				[(UIButton*)subview setEnabled:NO];
	}
}

- (void)enableButtons
{
	// iPhone or iPad?
	if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
	{
		// iPad: enable buttons in all views
		for( UIView *view in [pageContent allValues] )
		{
			for( UIView *subview in view.subviews )
				if( [subview isKindOfClass:[UIButton class]] )
					[(UIButton*)subview setEnabled:YES];
		}
	}
	else
	{
		// iPhone: enumerate subviews of mainscroller and enable all buttons
		for( UIView *subview in mainScroller.subviews )
			if( [subview isKindOfClass:[UIButton class]] )
				[(UIButton*)subview setEnabled:YES];
	}
}

- (void)setCurrentButtonsView:(UIView*)currentButtonsView
{
	// Remove old buttons view
	/// TEMP: fancy animation here!
	[_currentButtonsView removeFromSuperview];
	
	// Update ivar
	_currentButtonsView = currentButtonsView;
	
	// Add and fade in new buttons view
	_currentButtonsView.alpha = 0;
	[self.view insertSubview:_currentButtonsView belowSubview:debugView];
	[UIView animateWithDuration:0.3f animations:^{
		_currentButtonsView.alpha = 1;
	}];
}

- (IBAction)scanAction:(id)sender
{
	// Show HUD
	[MBProgressHUD showHUDAddedTo:self.view animated:YES];
	
	// Forget existing
	[peripherals removeAllObjects];
	[peripheralNames removeAllObjects];
	
	// Start scanning - we're only looking for devices with the "Generic Command and Control Protocol" service
	[self print:@"Start scanning..."];
	scanTimer = [NSTimer scheduledTimerWithTimeInterval:2.0f target:self selector:@selector(scanTimeout:) userInfo:nil repeats:NO];
	[centralManager scanForPeripheralsWithServices:[NSArray arrayWithObject:[CBUUID UUIDWithString:UUID_GCAC_SERVICE]] options:0];
	
	// Set toolbar items
	if( [toolbarItems containsObject:learnButton] )
	{
		[toolbarItems insertObject:scanButton atIndex:[toolbarItems indexOfObject:learnButton]];
		[toolbarItems removeObject:learnButton];
	}

	scanButton.enabled = NO;
	[toolbar setItems:toolbarItems animated:YES];
}

- (IBAction)disconnectAction:(id)sender
{
	if( self.connectedPeripheral == nil )
	{
		[self print:@"Not connected."];
		return;
	}

	[self print:@"Disconnecting..."];
	[centralManager cancelPeripheralConnection:connectedPeripheral];
}

- (IBAction)clearAction:(id)sender
{
	textView.text = @"";
}

- (IBAction)forgetPreferredAction:(id)sender
{
	// Forget preferred device
	APP.preferredDeviceUUID = nil;
}

- (IBAction)readAction:(id)sender
{
	if( self.connectedPeripheral == nil )
	{
		[self print:@"Not connected."];
		return;
	}
	
	[self print:@"Reading response characteristic..."];
	[connectedPeripheral readValueForCharacteristic:GCACResponseCharacteristic];
}

- (IBAction)learn:(id)sender
{
	// Toggle recording
	learning = !learning;
	
	// Change font color on all buttons
	// iPhone or iPad?
	if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
	{
		// iPad: all pages
		for( UIView *view in [pageContent allValues] )
		{
			// Individual buttons
			for( UIView *subview in view.subviews )
			{
				if( [subview isKindOfClass:[UIButton class]] )
				{
					UIButton *button = (UIButton*)subview;	// Typecast
					if( learning )
					{
						[button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
						[button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
					}
					else 
					{
						[button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
						[button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
					}
				}
			}
		}
	}
	else
	{
		// iPhone: use mainScroller
		[mainScroller.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			if( [obj isKindOfClass:[UIButton class]] )
			{
				UIButton *button = (UIButton*)obj;	// Typecast
				if( learning )
				{
					[button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
					[button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
				}
				else 
				{
					[button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
					[button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
				}
			}
		}];
	}
}

- (IBAction)toggleDebugAction:(id)sender
{
	// Is the debugging view already visible?
	if( debugView.frame.origin.y < self.view.bounds.size.height )
	{
		// Yes: hide it
		CGRect frame = debugView.frame;
		frame.origin.y = self.view.bounds.size.height;
		
		[UIView animateWithDuration:0.3 animations:^{
			debugView.frame = frame;
		}];
	}
	else
	{
		// No: show it
		CGRect frame = debugView.frame;
		frame.origin.y = self.view.bounds.size.height - frame.size.height;
		
		// Weirdness happens here…
		// When we show the debug view, the textView is not updates to show the text.
		// But as soon as the user scrolls the view, it becomes visible.
		// See http://stackoverflow.com/questions/7738666/uitextview-doesnt-show-until-it-is-scrolled
		// Therefore, we clear the text and set it again. Dangit, that should not be necessary!
		DEBUG_LOG( @"Performing ugly hack..." );
		NSString *tmpText = textView.text;
		textView.text = @"";
		textView.text = tmpText;
		[textView scrollRangeToVisible:NSMakeRange( [textView.text length]-1, 1 )];

		[UIView animateWithDuration:0.3 animations:^{
			debugView.frame = frame;
		}];
	}
}

- (IBAction)debug1Action:(id)sender
{
	BOOL isEnabled;
	
	// iPhone or iPad?
	if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
	{
		// iPad: get first button from currentButtonsView
		for( UIView *subview in _currentButtonsView.subviews )
		{
			if( [subview isKindOfClass:[UIButton class]] )
			{
				isEnabled = [(UIButton*)subview isEnabled];
				break;
			}
		}
	}
	else
	{
		// iPhone: get first button in mainScroller
		for( UIView *subview in mainScroller.subviews )
		{
			if( [subview isKindOfClass:[UIButton class]] )
			{
				isEnabled = [(UIButton*)subview isEnabled];
				break;
			}
		}
	}

	// Enable or disable all buttons
	if( isEnabled )
	{
		[self disableButtons];
		
		// Set toolbar items
		if( [toolbarItems containsObject:learnButton] )
		{
			[toolbarItems insertObject:scanButton atIndex:[toolbarItems indexOfObject:learnButton]];
			[toolbarItems removeObject:learnButton];
		}
		[toolbar setItems:toolbarItems animated:YES];
	}
	else 
	{
		[self enableButtons];
		
		// Set toolbar items
		if( [toolbarItems containsObject:scanButton] )
		{
			[toolbarItems insertObject:learnButton atIndex:[toolbarItems indexOfObject:scanButton]];
			[toolbarItems removeObject:scanButton];
		}
		[toolbar setItems:toolbarItems animated:YES];
	}
}

- (IBAction)sendLearnAction:(id)sender
{
	if( self.connectedPeripheral == nil )
	{
		[self print:@"Not connected."];
		return;
	}
	
	[self print:@"Sending \"L-000\""];
	[connectedPeripheral writeValue:[@"L-000" dataUsingEncoding:NSUTF8StringEncoding] forCharacteristic:GCACCommandCharacteristic type:CBCharacteristicWriteWithResponse];
}

- (IBAction)sendTAction:(id)sender
{
	if( self.connectedPeripheral == nil )
	{
		[self print:@"Not connected."];
		return;
	}
	
	[self print:@"Sending \"T-000\""];
	[connectedPeripheral writeValue:[@"T-000" dataUsingEncoding:NSUTF8StringEncoding] forCharacteristic:GCACCommandCharacteristic type:CBCharacteristicWriteWithResponse];
}

- (IBAction)sendYAction:(id)sender
{
	if( self.connectedPeripheral == nil )
	{
		[self print:@"Not connected."];
		return;
	}
	
	[self print:@"Sending \"Y-000\""];
	[connectedPeripheral writeValue:[@"Y-000" dataUsingEncoding:NSUTF8StringEncoding] forCharacteristic:GCACCommandCharacteristic type:CBCharacteristicWriteWithResponse];
}

@end
