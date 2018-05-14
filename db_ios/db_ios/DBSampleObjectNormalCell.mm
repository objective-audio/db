//
//  DBSampleObjectNormalCell.m
//

#import "DBSampleObjectNormalCell.h"
#import "yas_cf_utils.h"

using namespace yas;

@implementation DBSampleObjectNormalCell

- (void)prepareForReuse {
    [super prepareForReuse];

    self.textLabel.text = nil;
}

- (void)setupWithTitle:(std::string const &)title {
    self.textLabel.text = (__bridge NSString *)to_cf_object(title);
}

@end
